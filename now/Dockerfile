FROM google/cloud-sdk:alpine

RUN apk --no-cache add jq bash curl nodejs npm && \
    npm i -g npm now && \
    curl -L https://storage.googleapis.com/berglas/main/linux_amd64/berglas -o /usr/local/bin/berglas && \
    chmod +x /usr/local/bin/berglas
RUN gcloud components install beta --quiet

COPY "entrypoint.sh" "/entrypoint.sh"
ENTRYPOINT ["/entrypoint.sh"]
