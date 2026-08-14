FROM ghcr.io/erebe/wstunnel:latest

# Render завершает внешний TLS и передаёт WebSocket в контейнер по HTTP/WS.
# Публичный адрес при этом будет использоваться как wss://...
ENV RUST_LOG=info

CMD ["sh", "-c", "exec /home/app/wstunnel server --restrict-http-upgrade-path-prefix \"${WSTUNNEL_PATH}\" ws://0.0.0.0:${PORT}"]
