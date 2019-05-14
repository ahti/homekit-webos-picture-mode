FROM swift:5.0.1

RUN apt-get update && apt-get install -y libsodium-dev libavahi-compat-libdnssd-dev openssl libssl-dev

ADD . /app

RUN cd /app && swift build -c release

VOLUME /data
WORKDIR /data

CMD /app/.build/release/homekit-webos-picture-mode
