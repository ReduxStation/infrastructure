<?php
// Polls the DreamDaemon /world/Topic ?status endpoint and writes a
// serverinfo.json that the public-log-parser polls for ongoing-round
// protection. Decoupled from the game so we don't need DMAPI TGS events
// firing on round start/end. Mirrors the tgstation13.org/getserverdata.php
// pattern, scoped to a single server.

$host        = getenv('GAME_HOST') ?: 'tgs';
$port        = (int) (getenv('GAME_PORT') ?: 1337);
$identifier  = getenv('SERVER_IDENTIFIER') ?: 'owo';
$output_path = getenv('OUTPUT_PATH') ?: '/srv/output/serverinfo.json';
$timeout_s   = 2;

function byond_query(string $addr, int $port, string $query, int $timeout_s): ?string {
    if ($query[0] !== '?') {
        $query = '?' . $query;
    }
    // Reverse-engineered BYOND world.Topic wire format:
    //   [magic 2B = 0x0083] [len 2B big-endian = strlen(query)+6] [zeros 5B] [query] [null 1B]
    $packet = "\x00\x83" . pack('n', strlen($query) + 6) . "\x00\x00\x00\x00\x00" . $query . "\x00";

    $sock = @stream_socket_client("tcp://$addr:$port", $errno, $errstr, $timeout_s);
    if (!$sock) {
        fwrite(STDERR, "[serverinfo] cannot connect to $addr:$port: $errstr ($errno)\n");
        return null;
    }
    stream_set_timeout($sock, $timeout_s);

    $sent = 0;
    $total = strlen($packet);
    while ($sent < $total) {
        $w = @fwrite($sock, substr($packet, $sent));
        if ($w === false || $w === 0) {
            fclose($sock);
            fwrite(STDERR, "[serverinfo] write failed at byte $sent\n");
            return null;
        }
        $sent += $w;
    }

    $response = @stream_get_contents($sock, 65535);
    fclose($sock);

    if ($response === false || strlen($response) < 5) {
        return null;
    }
    // Response: [0x00] [0x83] [size 2B big-endian] [type 1B] [payload size-1 bytes]
    if ($response[0] !== "\x00" || $response[1] !== "\x83") {
        return null;
    }
    $size_unpacked = unpack('n', $response[2] . $response[3]);
    $size = $size_unpacked[1] - 1;
    $type = $response[4];
    if ($type !== "\x06") {
        // 0x06 = ASCII string. 0x2a = float. Status returns a string for us.
        return null;
    }
    return substr($response, 5, $size);
}

function parse_status(string $raw): array {
    // BYOND returns key1=value1&key2=value2&... (URL-encoded values).
    $raw = str_replace("\x00", "", $raw);
    $out = [];
    foreach (explode('&', $raw) as $pair) {
        $kv = explode('=', $pair, 2);
        $key = urldecode($kv[0]);
        $out[$key] = isset($kv[1]) ? urldecode($kv[1]) : null;
    }
    return $out;
}

$raw = byond_query($host, $port, '?status', $timeout_s);
$status = ($raw !== null) ? parse_status($raw) : null;

$has_active_round = $status && !empty($status['round_id']);

if ($has_active_round) {
    $payload = [
        'servers' => [
            [
                'data'       => array_merge($status, ['identifier' => $identifier]),
                'identifier' => $identifier,
                'retry_wait' => 0,
            ],
        ],
        'last_update' => gmdate('Y-m-d\TH:i:s.000\Z'),
    ];
} else {
    // DD not reachable or no round started yet. Empty server list = parser
    // shows everything (no rounds hidden). This is the correct stub during
    // deploys / world.New / outages.
    $payload = [
        'servers'     => [],
        'last_update' => gmdate('Y-m-d\TH:i:s.000\Z'),
    ];
}

$json = json_encode($payload, JSON_UNESCAPED_SLASHES);
$tmp  = $output_path . '.tmp';

$out_dir = dirname($output_path);
if (!is_dir($out_dir)) {
    @mkdir($out_dir, 0755, true);
}

if (@file_put_contents($tmp, $json) === false) {
    fwrite(STDERR, "[serverinfo] failed to write $tmp\n");
    exit(1);
}
if (!@rename($tmp, $output_path)) {
    fwrite(STDERR, "[serverinfo] failed to rename $tmp -> $output_path\n");
    exit(1);
}

$round = $has_active_round ? $status['round_id'] : 'none';
fwrite(STDERR, "[serverinfo] wrote $output_path round_id=$round\n");
