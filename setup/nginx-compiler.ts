#!/usr/bin/env bun

import { $ } from "bun";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

// Compiles nginx config files and outputs them directly to /etc/nginx/conf.d/
// with warnings before replacing existing files

// Get the absolute path to this file
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

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

async function checkAndWarnExistingFiles(outputDir: string, configFiles: string[]): Promise<void> {
  const existingFiles: string[] = [];
  
  for (const configFile of configFiles) {
    const outputPath = join(outputDir, configFile);
    try {
      await $`test -f ${outputPath}`;
      existingFiles.push(configFile);
    } catch {
      // File doesn't exist, continue
    }
  }
  
  if (existingFiles.length > 0) {
    console.log("⚠️  WARNING: The following files already exist and will be replaced:");
    existingFiles.forEach(file => console.log(`   - ${file}`));
    console.log(`   📁 Target directory: ${outputDir}`);
    console.log("   Press Ctrl+C to cancel, or wait 5 seconds to continue...\n");
    
    // Wait 5 seconds to allow user to cancel
    await new Promise(resolve => setTimeout(resolve, 5000));
    console.log("   ✅ Continuing with file replacement...\n");
  }
}

// Check if .env file exists
async function checkEnvFile(): Promise<boolean> {
  try {
    await $`test -f .env`;
    return true;
  } catch {
    return false;
  }
}

async function compileNginxConfig(
  templatePath: string,
  outputPath: string
): Promise<void> {
  console.log(`🐳 Compiling ${templatePath}...`);

  // Create random temp directory, delete before exiting
  const tempDir = "./temp-work/" + Math.random().toString(36).substring(2, 15);
  await $`mkdir -p ${tempDir}`;

  // Copy the template file to temp directory
  const tempTemplatePath = join(tempDir, "nginx.conf.template");
  await $`cp ${templatePath} ${tempTemplatePath}`;

  try {
    // Run tpl command in jitsi/base container using Bun Shell
    // Docker will automatically load .env file from current directory
    console.log("   🔧 Running tpl command in Docker container...");
    
    await $`docker run --rm \
      -v "${process.cwd()}/${tempDir}:/work" \
      --env-file .env \
      --entrypoint="" \
      jitsi/base:stable \
      sh -c "cd /work && tpl nginx.conf.template > nginx.conf.compiled"`;

    // Check if compiled file was created
    const compiledPath = join(tempDir, "nginx.conf.compiled");
    try {
      await $`test -f ${compiledPath}`;
    } catch {
      throw new Error("Compiled config file was not created");
    }

    // Copy to final location using sudo
    await $`sudo cp ${compiledPath} ${outputPath}`;

    console.log(`   ✅ Config compiled successfully to ${outputPath}`);
  } catch (error) {
    console.error("   ❌ Docker compilation failed:", error);
    throw new Error(
      "Failed to compile config with Docker. This is required for the script to work correctly."
    );
  } finally {
    // Delete temp directory
    await $`rm -rf ${tempDir}`;
  }
}

async function main(): Promise<void> {
  console.log("🚀 Starting nginx config compilation...\n");

  try {
    // Get sudo permission for writing to /etc/nginx
    await getSudoPermission();

    // Check if .env file exists (Bun automatically loads it)
    const envExists = await checkEnvFile();
    if (envExists) {
      console.log("   ✅ .env file found - Bun will automatically load environment variables\n");
    } else {
      console.log("   ⚠️  No .env file found - using empty environment\n");
    }

    // Set output directory to /etc/nginx/conf.d/
    const outputDir = "/etc/nginx/conf.d";
    await $`sudo mkdir -p ${outputDir}`;

    // Process all *.conf files in the proxy folder
    const proxyDir = join(__dirname, "../proxy");
    const configFiles = [
      "general.conf",
      "services.conf",
      "posthog.conf",
    ];

    // Check for existing files and warn user
    await checkAndWarnExistingFiles(outputDir, configFiles);

    for (const configFile of configFiles) {
      const templatePath = join(proxyDir, configFile);
      const outputPath = join(outputDir, configFile);

      try {
        await $`test -f ${templatePath}`;
        await compileNginxConfig(templatePath, outputPath);
        console.log();
      } catch {
        console.log(`   ⚠️  Skipping ${configFile} - file not found`);
      }
    }

    console.log("✨ All nginx config files compiled successfully!");
    console.log(`📁 Output directory: ${outputDir}`);

  } catch (error) {
    console.error("❌ Error during nginx config compilation:", error);
    process.exit(1);
  }
}

// Main execution
if (import.meta.main) {
  main();
}
