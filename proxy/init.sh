#!/bin/bash
set -e

echo "Starting Traefik initialization..."

# Create acme.json with proper permissions
if [ ! -f /data/acme.json ]; then
  touch /data/acme.json && chmod 600 /data/acme.json
  echo "Created acme.json with proper permissions"
else
  echo "acme.json already exists"
fi

# Prepare the dynamic configuration from the template
cp /traefik-dynamic.yml.template /config/traefik_dynamic.yml

JVB_MIDDLEWARES=""
JVB_SERVICES=""
JVB_ROUTERS=""

if [ -n "$JVB_INSTANCES" ]; then
  IFS=',' read -ra INSTANCES_ARRAY <<< "$JVB_INSTANCES"

  for i in "${!INSTANCES_ARRAY[@]}"; do
    instance="${INSTANCES_ARRAY[$i]}"
    index=$((i + 1))
    ip_var="JVB_${index}_PUBLIC_IP"
    ip_value=$(eval echo \$$ip_var)

    if [ -n "$ip_value" ]; then
      # Middlewares
      JVB_MIDDLEWARES="${JVB_MIDDLEWARES}
    ${instance}-path-strip:
      stripPrefix:
        prefixes:
          - \"/colibri-ws/${instance}\"
"
      # Services
      JVB_SERVICES="${JVB_SERVICES}
    ${instance}-service:
      loadBalancer:
        servers:
          - url: \"http://${ip_value}:9090\"
"
      # Routers
      JVB_ROUTERS="${JVB_ROUTERS}
    ${instance}-router:
      rule: \"Host(\`${XMPP_DOMAIN}\`) && PathPrefix(\`/colibri-ws/${instance}/\`)\"
      service: \"${instance}-service\"
      middlewares:
        - \"${instance}-path-strip\"
      entryPoints:
        - \"websecure\"
      tls:
        certResolver: \"myresolver\"
"
      echo "Configured JVB instance: $instance -> $ip_value:9090"
    else
      echo "Warning: No IP found for $instance (expected variable: $ip_var)"
    fi
  done
fi

# Use awk for robust multiline replacement
awk -v r="$JVB_MIDDLEWARES" '{gsub(/# JVB_MIDDLEWARES_PLACEHOLDER/,r)}1' /config/traefik_dynamic.yml > /config/temp.yml && mv /config/temp.yml /config/traefik_dynamic.yml
awk -v r="$JVB_SERVICES" '{gsub(/# JVB_SERVICES_PLACEHOLDER/,r)}1' /config/traefik_dynamic.yml > /config/temp.yml && mv /config/temp.yml /config/traefik_dynamic.yml
awk -v r="$JVB_ROUTERS" '{gsub(/# JVB_ROUTERS_PLACEHOLDER/,r)}1' /config/traefik_dynamic.yml > /config/temp.yml && mv /config/temp.yml /config/traefik_dynamic.yml

# Use sed for the simple, single-line replacement
sed -i "s|\${POSTHOG_DOMAIN}|${POSTHOG_DOMAIN:-e.sonacove.com}|g" /config/traefik_dynamic.yml

echo "traefik_dynamic.yml generated successfully"
echo "JVB instances configured: $(echo "$JVB_INSTANCES" | tr ',' ' ')"
echo "PostHog proxy configured for ${POSTHOG_DOMAIN:-e.sonacove.com}"
echo "Initialization complete!"
