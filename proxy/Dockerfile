FROM alpine:latest

# Install necessary packages
RUN apk add --no-cache bash

# Copy the init script
COPY init.sh /init.sh
RUN chmod +x /init.sh

# Set the entrypoint
ENTRYPOINT ["/init.sh"] 