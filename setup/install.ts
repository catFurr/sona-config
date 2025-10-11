// This script is run to setup NGINX and SSL on a new server
// or to update an existing server with new configuration (for example if 
// the proxy conf file is changed).

import { $ } from "bun";


const email = 'thirdparty@sonacove.com';

// Check if certificates already exist
async function certsExist(xmppDomain: string): Promise<boolean> {
  try {
    const result = await $`test -f /etc/letsencrypt/live/${xmppDomain}/fullchain.pem`.nothrow();
    return result.exitCode === 0;
  } catch {
    return false;
  }
}

// Get sudo permission at the start
async function getSudoPermission() {
  console.log('🔐 Requesting sudo permission...');
  try {
    await $`sudo -v`;
    console.log('✅ Sudo permission granted');
  } catch (error) {
    console.error('❌ Failed to get sudo permission:', error);
    process.exit(1);
  }
}

// Step 1: Generate certificate for your domain
async function generateCertificate(xmppDomain: string) {
  console.log(`🔐 Generating certificate for ${xmppDomain}...`);
  
  try {
    await $`sudo certbot certonly --standalone -d ${xmppDomain} --non-interactive --agree-tos --email ${email}`;
    console.log('✅ Certificate generated successfully');
  } catch (error) {
    console.error('❌ Failed to generate certificate:', error);
    throw error;
  }
}

// Step 2: Create Symbolic Links for Nginx
async function createSslSymlinks(xmppDomain: string) {
  console.log('🔗 Creating SSL symbolic links...');
  
  try {
    // Create SSL directories if they don't exist
    await $`sudo mkdir -p /etc/ssl/certs /etc/ssl/private`;
    
    // Create symbolic links from Let's Encrypt to standard locations
    await $`sudo ln -sf /etc/letsencrypt/live/${xmppDomain}/fullchain.pem /etc/ssl/certs/${xmppDomain}.crt`;
    await $`sudo ln -sf /etc/letsencrypt/live/${xmppDomain}/privkey.pem /etc/ssl/private/${xmppDomain}.key`;
    
    // Verify links were created
    console.log('📋 Verifying SSL links...');
    await $`sudo ls -la /etc/ssl/certs/${xmppDomain}.crt`;
    await $`sudo ls -la /etc/ssl/private/${xmppDomain}.key`;
    
    console.log('✅ SSL symbolic links created successfully');
  } catch (error) {
    console.error('❌ Failed to create SSL symbolic links:', error);
    throw error;
  }
}

// Step 3: Generate DH Parameters
async function generateDhParams() {
  console.log('🔐 Generating DH parameters...');
  
  try {
    await $`sudo openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048`;
    console.log('✅ DH parameters generated successfully');
  } catch (error) {
    console.error('❌ Failed to generate DH parameters:', error);
    throw error;
  }
}

// Step 4: Reload NGINX
async function reloadNginx() {
  console.log('🔄 Reloading NGINX...');
  
  try {
    // Verify nginx configuration
    console.log('📋 Verifying NGINX configuration...');
    await $`sudo nginx -t`;
    
    // Restart nginx
    await $`sudo systemctl reload nginx`;
    console.log('✅ NGINX reloaded successfully');
  } catch (error) {
    console.error('❌ Failed to reload NGINX:', error);
    throw error;
  }
}

// Step 5: Restart all containers
async function restartContainers() {
  console.log('🐳 Restarting Docker containers...');
  
  try {
    await $`docker compose down`;
    await $`docker compose up -d`;
    console.log('✅ Docker containers restarted successfully');
  } catch (error) {
    console.error('❌ Failed to restart Docker containers:', error);
    throw error;
  }
}

// Main execution function
async function main() {
  console.log('🚀 Starting Sonacove installation script...');
  
  try {
    // Get XMPP domain from environment (Bun automatically loads .env files)
    const xmppDomain = process.env.XMPP_DOMAIN;
    
    if (!xmppDomain) {
      console.error('❌ XMPP_DOMAIN not found in environment variables. Make sure .env file exists and contains XMPP_DOMAIN');
      process.exit(1);
    }
    
    console.log(`📋 Using XMPP domain: ${xmppDomain}`);
    
    // Get sudo permission
    await getSudoPermission();
    
    // Check if certificates already exist
    const certsAlreadyExist = await certsExist(xmppDomain);
    
    if (certsAlreadyExist) {
      console.log('ℹ️  Certificates already exist, skipping certificate generation steps');
    } else {
      console.log('ℹ️  Certificates not found, will generate new ones');
      
      // Step 1: Generate certificate
      await generateCertificate(xmppDomain);
      
      // Step 2: Create SSL symbolic links
      await createSslSymlinks(xmppDomain);
      
      // Step 3: Generate DH parameters
      await generateDhParams();
    }
    
    // Step 4: Reload NGINX
    await reloadNginx();
    
    // Step 5: Restart all containers
    await restartContainers();
    
    console.log('🎉 Installation completed successfully!');
    
  } catch (error) {
    console.error('💥 Installation failed:', error);
    process.exit(1);
  }
}

// Run the script
if (import.meta.main) {
  main();
}

