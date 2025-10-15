import { mkdir, writeFile, readFile, exists, rm } from "fs/promises";
import { join } from "path";
import { exec } from "child_process";
import { promisify } from "util";
import yaml from "yaml";
import type { CompilationOptions } from "./types.js";


const execAsync = promisify(exec);

async function loadFromEnvFile(
    envFilePath: string,
    envVarsNeeded: Set<string>,
    envVars: Record<string, string>
  ): Promise<number> {
    const envContent = await readFile(envFilePath, "utf-8");
    const envLines = envContent
      .split("\n")
      .filter((line) => line.trim() && !line.trim().startsWith("#"));

    let loadedCount = 0;
    for (const line of envLines) {
      const [key, ...valueParts] = line.split("=");
      if (key && valueParts.length > 0) {
        const trimmedKey = key.trim();
        // Only load if this variable is needed for lookup and not already set
        if (envVarsNeeded.has(trimmedKey) && !envVars[trimmedKey]) {
          const value = valueParts.join("=").replace(/^["']|["']$/g, ""); // Remove quotes
          envVars[trimmedKey] = value.trim();
          loadedCount++;
          console.log(
            `   📋 Loaded from .env: ${trimmedKey} = "${value.trim()}"`
          );
        }
      }
    }
    return loadedCount;
}

export async function loadEnvironmentVariables(
  containerName: string,
  composeFilePath: string,
  envFilePath?: string
): Promise<Record<string, string>> {
  console.log("🔧 Loading environment variables...");

  // Parse compose file to extract environment variables
  const composeContent = await readFile(composeFilePath, "utf-8");
  const composeData = yaml.parse(composeContent);

  const envVars: Record<string, string> = {};
  const envVarsNeedingLookup = new Set<string>();

  // Extract environment variables from compose file
  const containerService = composeData?.services?.[containerName];
  if (containerService?.environment) {
    for (const envEntry of containerService.environment) {
      if (typeof envEntry === "string") {
        const equalIndex = envEntry.indexOf("=");
        if (equalIndex > 0) {
          const key = envEntry.substring(0, equalIndex).trim();
          const value = envEntry
            .substring(equalIndex + 1)
            .trim()
            .replace(/^["']|["']$/g, ""); // Remove quotes

          if (value.startsWith("${") && value.endsWith("}")) {
            // This is a variable reference like KEY=${VAR}
            const varName = value.slice(2, -1);
            envVarsNeedingLookup.add(varName);
            console.log(
              `   📋 Found variable reference: ${key} = \${${varName}}`
            );
          } else {
            // This is a direct value like KEY=value
            envVars[key] = value;
            console.log(`   ✅ Found direct value: ${key} = "${value}"`);
          }
        }
      }
    }
  }

  console.log(
    `   📊 Direct values from compose: ${Object.keys(envVars).length}`
  );
  console.log(`   📊 Variables needing lookup: ${envVarsNeedingLookup.size}`);

  // Load from .env file if specified and exists
  if (envFilePath && (await exists(envFilePath))) {
    const loadedFromEnv = await loadFromEnvFile(
      envFilePath,
      envVarsNeedingLookup,
      envVars
    );
    console.log(`   📋 Loaded ${loadedFromEnv} variables from .env file`);
  } else if (envFilePath) {
    console.log(
      "   ⚠️  No .env file found, variables will be left empty"
    );
  }

  console.log(
    `   ✅ Total environment variables loaded: ${Object.keys(envVars).length}`
  );
  return envVars;
}

export async function compileConfigWithDocker(options: CompilationOptions): Promise<void> {
  console.log("🐳 Compiling config with Docker...");

  // Create random temp directory, delete before exiting
  const tempDir = "./temp-work/" + Math.random().toString(36).substring(2, 15);
  await mkdir(tempDir, { recursive: true });

  // Create environment file for Docker
  const envContent = Object.entries(options.envVars)
    .map(([key, value]) => `${key}=${value}`)
    .join("\n");

  const envFile = join(tempDir, ".env");
  await writeFile(envFile, envContent);

  // Copy the template file to temp directory
  const tempTemplatePath = join(tempDir, "jvb.conf.template");
  const templateContent = await readFile(options.templatePath, "utf-8");
  await writeFile(tempTemplatePath, templateContent);

  try {
    // Run tpl command in jitsi/base container
    const dockerCommand = `docker run --rm \
      -v "${process.cwd()}/${tempDir}:/work" \
      --env-file "${process.cwd()}/${envFile}" \
      --entrypoint="" \
      jitsi/base:stable \
      sh -c "cd /work && tpl jvb.conf.template > jvb.conf.compiled"`;

    console.log("   🔧 Running tpl command in Docker container...");
    await execAsync(dockerCommand);

    // Move compiled file to desired output location
    const compiledPath = join(tempDir, "jvb.conf.compiled");
    if (!(await exists(compiledPath))) {
      throw new Error("Compiled config file was not created");
    }

    // Copy to final location
    const compiledContent = await readFile(compiledPath, "utf-8");
    await writeFile(options.outputPath, compiledContent);

    console.log("   ✅ Config compiled successfully");
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
