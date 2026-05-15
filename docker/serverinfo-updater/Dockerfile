FROM php:8.2-cli-alpine

RUN apk add --no-cache bash

WORKDIR /app
COPY update.php entrypoint.sh ./
RUN chmod +x entrypoint.sh

ENV GAME_HOST=tgs
ENV GAME_PORT=1337
ENV SERVER_IDENTIFIER=owo
ENV OUTPUT_PATH=/srv/output/serverinfo.json
ENV POLL_INTERVAL=30

CMD ["./entrypoint.sh"]
