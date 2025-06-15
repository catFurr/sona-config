import { mkdir, writeFile, readFile, exists } from "fs/promises";
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

function applyFallbackValues(
    envVarsNeeded: Set<string>,
    envVars: Record<string, string>
  ): number {
    const fallbackValues: Record<string, string> = {
      JVB_AUTH_PASSWORD: "defaultpassword",
      XMPP_SERVER: "xmpp.meet.example.com",
    };

    let fallbacksUsed = 0;
    for (const varName of envVarsNeeded) {
      if (!envVars[varName]) {
        if (fallbackValues[varName]) {
          envVars[varName] = fallbackValues[varName];
          console.log(
            `   📝 Using fallback for ${varName} = "${fallbackValues[varName]}"`
          );
          fallbacksUsed++;
        } else {
          console.log(
            `   ⚠️  No fallback available for ${varName}, leaving empty`
          );
          envVars[varName] = "";
        }
      }
    }
    return fallbacksUsed;
}

export async function loadEnvironmentVariables(
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
  const jvbService = composeData?.services?.jvb;
  if (jvbService?.environment) {
    for (const envEntry of jvbService.environment) {
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
      "   ⚠️  No .env file found, will use fallback values if needed"
    );
  }

  // Add fallback values for missing variables
  const fallbacksUsed = applyFallbackValues(
    envVarsNeedingLookup,
    envVars
  );

  console.log(
    `   ✅ Total environment variables loaded: ${Object.keys(envVars).length}`
  );
  return envVars;
}

export async function compileConfigWithDocker(options: CompilationOptions): Promise<void> {
  console.log("🐳 Compiling config with Docker...");

  const tempDir = "./temp-work";
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
  }
}
