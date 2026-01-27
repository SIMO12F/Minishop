FROM alpine:3.20
RUN apk add --no-cache curl ca-certificates
ARG KUBECTL_VERSION=v1.34.0
RUN curl -L --retry 5 -o /usr/local/bin/kubectl https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl \
 && chmod +x /usr/local/bin/kubectl
ENTRYPOINT ["kubectl"]
