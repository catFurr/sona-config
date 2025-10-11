#!/usr/bin/env bun

import { mkdir, writeFile, readFile, exists, rm } from "fs/promises";
import { join, dirname } from "path";
import { exec } from "child_process";
import { promisify } from "util";
import { fileURLToPath } from "url";

// Compiles nginx config files and outputs them directly to /etc/nginx/conf.d/
// with warnings before replacing existing files


const execAsync = promisify(exec);

// Get the absolute path to this file
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

async function checkAndWarnExistingFiles(outputDir: string, configFiles: string[]): Promise<void> {
  const existingFiles: string[] = [];
  
  for (const configFile of configFiles) {
    const outputPath = join(outputDir, configFile);
    if (await exists(outputPath)) {
      existingFiles.push(configFile);
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

async function loadFromEnvFile(
    envFilePath: string,
    envVars: Record<string, string>
  ): Promise<number> {
    if (!(await exists(envFilePath))) {
      console.log("   ⚠️  No .env file found, using empty environment");
      return 0;
    }

    const envContent = await readFile(envFilePath, "utf-8");
    const envLines = envContent
      .split("\n")
      .filter((line) => line.trim() && !line.trim().startsWith("#"));

    let loadedCount = 0;
    for (const line of envLines) {
      const [key, ...valueParts] = line.split("=");
      if (key && valueParts.length > 0) {
        const trimmedKey = key.trim();
        const value = valueParts.join("=").replace(/^["']|["']$/g, "").trim();
        envVars[trimmedKey] = value;
        loadedCount++;
        console.log(`   📋 Loaded from .env: ${trimmedKey} = "${value}"`);
      }
    }
    return loadedCount;
}

async function compileNginxConfig(
  templatePath: string,
  outputPath: string,
  envVars: Record<string, string>
): Promise<void> {
  console.log(`🐳 Compiling ${templatePath}...`);

  // Create random temp directory, delete before exiting
  const tempDir = "./temp-work/" + Math.random().toString(36).substring(2, 15);
  await mkdir(tempDir, { recursive: true });

  // Create environment file for Docker
  const envContent = Object.entries(envVars)
    .map(([key, value]) => `${key}=${value}`)
    .join("\n");

  const envFile = join(tempDir, ".env");
  await writeFile(envFile, envContent);

  // Copy the template file to temp directory
  const tempTemplatePath = join(tempDir, "nginx.conf.template");
  const templateContent = await readFile(templatePath, "utf-8");
  await writeFile(tempTemplatePath, templateContent);

  try {
    // Run tpl command in jitsi/base container
    const dockerCommand = `docker run --rm \\
      -v "${process.cwd()}/${tempDir}:/work" \\
      --env-file "${process.cwd()}/${envFile}" \\
      --entrypoint="" \\
      jitsi/base:stable \\
      sh -c "cd /work && tpl nginx.conf.template > nginx.conf.compiled"`;

    console.log("   🔧 Running tpl command in Docker container...");
    await execAsync(dockerCommand);

    // Move compiled file to desired output location
    const compiledPath = join(tempDir, "nginx.conf.compiled");
    if (!(await exists(compiledPath))) {
      throw new Error("Compiled config file was not created");
    }

    // Copy to final location
    const compiledContent = await readFile(compiledPath, "utf-8");
    await writeFile(outputPath, compiledContent);

    console.log(`   ✅ Config compiled successfully to ${outputPath}`);
  } catch (error) {
    console.error("   ❌ Docker compilation failed:", error);
    throw new Error(
      "Failed to compile config with Docker. This is required for the script to work correctly."
    );
  } finally {
    // Delete temp directory
    await rm(tempDir, { recursive: true });
  }
}

async function main(): Promise<void> {
  console.log("🚀 Starting nginx config compilation...\n");

  try {
    // Load environment variables from .env file
    const envVars: Record<string, string> = {};
    const envFilePath = join(__dirname, "../.env");
    const loadedCount = await loadFromEnvFile(envFilePath, envVars);
    console.log(`   ✅ Loaded ${loadedCount} environment variables\n`);

    // Set output directory to /etc/nginx/conf.d/
    const outputDir = "/etc/nginx/conf.d";
    await mkdir(outputDir, { recursive: true });

    // Process all *.conf files in the proxy folder
    const proxyDir = join(__dirname, "../proxy");
    const configFiles = [
      "general.conf",
      "services.conf",
    ];

    // Check for existing files and warn user
    await checkAndWarnExistingFiles(outputDir, configFiles);

    for (const configFile of configFiles) {
      const templatePath = join(proxyDir, configFile);
      const outputPath = join(outputDir, configFile);

      if (await exists(templatePath)) {
        await compileNginxConfig(templatePath, outputPath, envVars);
        console.log();
      } else {
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
