# ╔═════════════════════════════════════════════════════╗
# ║ IMAGE                                               ║
# ╚═════════════════════════════════════════════════════╝
FROM scratch
WORKDIR /app
COPY goreleaser-example /
USER 65534:65534
EXPOSE 8080
ENTRYPOINT ["/goreleaser-example"]
