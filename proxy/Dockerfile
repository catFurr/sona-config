FROM alpine:latest

# Install necessary packages
RUN apk add --no-cache bash

# Copy the init script and the template
COPY init.sh /init.sh
COPY traefik-dynamic.yml.template /traefik-dynamic.yml.template
RUN chmod +x /init.sh

# Set the entrypoint
ENTRYPOINT ["/init.sh"] 