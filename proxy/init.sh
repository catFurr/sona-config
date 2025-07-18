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

# Generate traefik_dynamic.yml
echo "Generating traefik_dynamic.yml..."
cat > /config/traefik_dynamic.yml << 'EOF'
http:
  middlewares:
    # Common security headers for most services
    common-security-headers:
      headers:
        stsSeconds: 63072000 # Strict-Transport-Security: max-age= (1 year)
        stsIncludeSubdomains: true
        forceSTSHeader: true
        # stsPreload: true # Consider adding if you submit your domain for HSTS preloading
        customFrameOptionsValue: "SAMEORIGIN" # X-Frame-Options
        contentTypeNosniff: true # X-Content-Type-Options
        browserXssFilter: true # X-XSS-Protection (uses Traefik's default, which is "1; mode=block")
        customResponseHeaders:
          Referrer-Policy: "strict-origin-when-cross-origin"

    # Compression middleware for text-based responses
    compress-middleware:
      compress: {}
EOF

# Generate JVB-specific configurations
if [ -n "$JVB_INSTANCES" ]; then
  echo '    # JVB path stripping middlewares' >> /config/traefik_dynamic.yml
  
  # Parse JVB instances and generate middlewares
  IFS=','
  for instance in $JVB_INSTANCES; do
    echo "    $instance-path-strip:" >> /config/traefik_dynamic.yml
    echo "      stripPrefix:" >> /config/traefik_dynamic.yml
    echo "        prefixes:" >> /config/traefik_dynamic.yml
    echo "          - \"/colibri-ws/$instance\"" >> /config/traefik_dynamic.yml
    echo "" >> /config/traefik_dynamic.yml
  done

  # Generate services section
  echo '  # JVB service definitions' >> /config/traefik_dynamic.yml
  echo '  services:' >> /config/traefik_dynamic.yml
  
  # Convert comma-separated list to array for indexing
  IFS=',' read -ra INSTANCES_ARRAY <<< "$JVB_INSTANCES"
  
  for i in "${!INSTANCES_ARRAY[@]}"; do
    instance="${INSTANCES_ARRAY[$i]}"
    # Use 1-based indexing for environment variables (JVB_1_PUBLIC_IP, JVB_2_PUBLIC_IP, etc.)
    index=$((i + 1))
    ip_var="JVB_${index}_PUBLIC_IP"
    
    ip_value=$(eval echo \$$ip_var)
    
    if [ -n "$ip_value" ]; then
      echo "    $instance-service:" >> /config/traefik_dynamic.yml
      echo "      loadBalancer:" >> /config/traefik_dynamic.yml
      echo "        servers:" >> /config/traefik_dynamic.yml
      echo "          - url: \"http://$ip_value:9090\"" >> /config/traefik_dynamic.yml
      echo "" >> /config/traefik_dynamic.yml
      echo "Configured JVB instance: $instance -> $ip_value:9090"
    else
      echo "Warning: No IP found for $instance (expected variable: $ip_var)"
    fi
  done

  # Generate routers section
  echo '  # JVB router definitions' >> /config/traefik_dynamic.yml
  echo '  routers:' >> /config/traefik_dynamic.yml
  
  for i in "${!INSTANCES_ARRAY[@]}"; do
    instance="${INSTANCES_ARRAY[$i]}"
    # Use 1-based indexing for environment variables
    index=$((i + 1))
    ip_var="JVB_${index}_PUBLIC_IP"
    ip_value=$(eval echo \$$ip_var)
    
    if [ -n "$ip_value" ]; then
      echo "    $instance-router:" >> /config/traefik_dynamic.yml
      echo "      rule: \"Host(\`$XMPP_DOMAIN\`) && PathPrefix(\`/colibri-ws/$instance/\`)\"" >> /config/traefik_dynamic.yml
      echo "      service: \"$instance-service\"" >> /config/traefik_dynamic.yml
      echo "      middlewares:" >> /config/traefik_dynamic.yml
      echo "        - \"$instance-path-strip\"" >> /config/traefik_dynamic.yml
      echo "      entryPoints:" >> /config/traefik_dynamic.yml
      echo "        - \"websecure\"" >> /config/traefik_dynamic.yml
      echo "      tls:" >> /config/traefik_dynamic.yml
      echo "        certResolver: \"myresolver\"" >> /config/traefik_dynamic.yml
      echo "" >> /config/traefik_dynamic.yml
    fi
  done
fi

echo "traefik_dynamic.yml generated successfully"
echo "JVB instances configured: $(echo "$JVB_INSTANCES" | tr ',' ' ')"
echo "Initialization complete!" 