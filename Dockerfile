FROM golang:1.8.3 as rexray-dev

WORKDIR /go/src/github.com/codedellemc/rexray

COPY . .

RUN go generate
RUN go build

FROM alpine:3.5

COPY --from=rexray-dev /go/src/github.com/codedellemc/rexray/rexray /usr/bin/

RUN apk update
RUN apk add xfsprogs e2fsprogs ca-certificates

RUN mkdir -p /lib64 && ln -s /lib/libc.musl-x86_64.so.1 /lib64/ld-linux-x86-64.so.2
RUN mkdir -p /etc/rexray /run/docker/plugins /var/lib/libstorage/volumes

ENTRYPOINT [ "/usr/bin/rexray" ]
