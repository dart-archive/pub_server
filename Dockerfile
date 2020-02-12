FROM ubuntu:latest

USER root
RUN apt-get update && apt-get install git wget -y

RUN mkdir /app && cd /app && git clone https://github.com/dart-lang/pub_server.git
RUN cd /app && wget https://storage.googleapis.com/dart-archive/channels/stable/release/latest/linux_packages/dart_2.7.1-1_amd64.deb && dpkg -i dart_2.7.1-1_amd64.deb
RUN PATH="$PATH:/usr/lib/dart/bin" && chmod -R +x /usr/lib/dart/bin/*

RUN adduser pubserver --system -q && chown -R pubserver /app
USER pubserver

WORKDIR /app/pub_server
RUN cd /app/pub_server && /usr/lib/dart/bin/pub get
VOLUME [ "/app/packages-db" ]

EXPOSE 8080

CMD ["dart", "example/example.dart", "-d", "/app/packages-db"]
