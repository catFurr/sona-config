#!/usr/bin/env bun

import { mkdir, writeFile, readFile, exists, rm } from "fs/promises";
import { join } from "path";
import { exec } from "child_process";
import { promisify } from "util";
import yaml from "yaml";
import * as hocon from "@pushcorn/hocon-parser";

const execAsync = promisify(exec);

// Configuration
const GITHUB_URLS = {
  jvbReference:
    "https://raw.githubusercontent.com/jitsi/jitsi-videobridge/master/jvb/src/main/resources/reference.conf",
  ice4jReference:
    "https://raw.githubusercontent.com/jitsi/ice4j/master/src/main/resources/reference.conf",
  dockerConfig:
    "https://raw.githubusercontent.com/jitsi/docker-jitsi-meet/master/jvb/rootfs/etc/cont-init.d/10-config",
  dockerJvbConf:
    "https://raw.githubusercontent.com/jitsi/docker-jitsi-meet/master/jvb/rootfs/defaults/jvb.conf",
  dockerLogging:
    "https://raw.githubusercontent.com/jitsi/docker-jitsi-meet/master/jvb/rootfs/defaults/logging.properties",
};

const DIRECTORIES = {
  reference: "./reference",
  dockerBuildContext: "./docker-build-context",
  tempWorkDir: "./temp-work",
};

interface ConfigStats {
  referenceFilesFetched: number;
  dockerFilesFetched: number;
  configCompiled: boolean;
  missingKeys: string[];
  typeMismatches: string[];
  customConfigUpdated: boolean;
  envVarsLoaded: number;
}

interface ConfigDifference {
  path: string;
  expectedValue: any;
  expectedType: string;
  actualValue?: any;
  actualType?: string;
  isMissing: boolean;
}

class ConfigFetcher {
  private stats: ConfigStats = {
    referenceFilesFetched: 0,
    dockerFilesFetched: 0,
    configCompiled: false,
    missingKeys: [],
    typeMismatches: [],
    customConfigUpdated: false,
    envVarsLoaded: 0,
  };

  async run(): Promise<void> {
    console.log("🚀 Starting Jitsi config update process...\n");

    try {
      // Step 1: Setup directories
      await this.setupDirectories();

      // Step 2: Load environment variables dynamically
      const envVars = await this.loadEnvironmentVariables();

      // Step 3: Fetch reference configs
      await this.fetchReferenceConfigs();

      // Step 4: Fetch docker build context files
      await this.fetchDockerBuildContext();

      // Step 5: Compile default config with environment variables
      await this.compileConfigWithDocker(envVars);

      // Step 6: Compare and update custom config
      await this.compareAndUpdateConfig();

      // Step 7: Print stats
      this.printStats();

      // Step 8: Cleanup
      await this.cleanup();
    } catch (error) {
      console.error("❌ Error during config update:", error);
      await this.cleanup();
      process.exit(1);
    }
  }

  private async setupDirectories(): Promise<void> {
    console.log("📁 Setting up directories...");

    for (const dir of Object.values(DIRECTORIES)) {
      if (!(await exists(dir))) {
        await mkdir(dir, { recursive: true });
        console.log(`   ✓ Created ${dir}`);
      }
    }
  }

  private async loadEnvironmentVariables(): Promise<Record<string, string>> {
    console.log("\n🔧 Loading environment variables...");

    // Parse compose file to extract environment variables
    const composeContent = await readFile("./compose.jvb.yml", "utf-8");
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

    // Read .env file if it exists and only load variables that need lookup
    const envFilePath = "../.env";
    let loadedFromEnv = 0;

    if (await exists(envFilePath)) {
      const envContent = await readFile(envFilePath, "utf-8");
      const envLines = envContent
        .split("\n")
        .filter((line) => line.trim() && !line.trim().startsWith("#"));

      for (const line of envLines) {
        const [key, ...valueParts] = line.split("=");
        if (key && valueParts.length > 0) {
          const trimmedKey = key.trim();
          // Only load if this variable is needed for lookup and not already set
          if (envVarsNeedingLookup.has(trimmedKey) && !envVars[trimmedKey]) {
            const value = valueParts.join("=").replace(/^["']|["']$/g, ""); // Remove quotes
            envVars[trimmedKey] = value.trim();
            loadedFromEnv++;
            console.log(
              `   📋 Loaded from .env: ${trimmedKey} = "${value.trim()}"`
            );
          }
        }
      }

      console.log(`   📋 Loaded ${loadedFromEnv} variables from .env file`);
    } else {
      console.log(
        "   ⚠️  No .env file found, will use fallback values if needed"
      );
    }

    // Add fallback values only for variables that still need values
    const fallbackValues: Record<string, string> = {
      JVB_AUTH_PASSWORD: "defaultpassword",
      XMPP_SERVER: "xmpp.meet.example.com",
    };

    let fallbacksUsed = 0;
    for (const varName of envVarsNeedingLookup) {
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

    console.log(
      `   ✅ Total environment variables loaded: ${Object.keys(envVars).length}`
    );
    console.log(
      `   📊 Direct: ${
        Object.keys(envVars).length - loadedFromEnv - fallbacksUsed
      }, From .env: ${loadedFromEnv}, Fallbacks: ${fallbacksUsed}`
    );

    this.stats.envVarsLoaded = Object.keys(envVars).length;
    return envVars;
  }

  private async fetchReferenceConfigs(): Promise<void> {
    console.log("\n📥 Fetching reference configs...");

    const downloads = [
      {
        url: GITHUB_URLS.jvbReference,
        path: join(DIRECTORIES.reference, "jvb-reference.conf"),
      },
      {
        url: GITHUB_URLS.ice4jReference,
        path: join(DIRECTORIES.reference, "ice4j-reference.conf"),
      },
    ];

    await Promise.all(
      downloads.map(async ({ url, path }) => {
        await this.downloadFile(url, path);
        this.stats.referenceFilesFetched++;
        console.log(`   ✓ Downloaded ${path}`);
      })
    );
  }

  private async fetchDockerBuildContext(): Promise<void> {
    console.log("\n📥 Fetching docker build context files...");

    const downloads = [
      {
        url: GITHUB_URLS.dockerConfig,
        path: join(DIRECTORIES.dockerBuildContext, "10-config"),
      },
      {
        url: GITHUB_URLS.dockerJvbConf,
        path: join(DIRECTORIES.dockerBuildContext, "jvb.conf"),
      },
      {
        url: GITHUB_URLS.dockerLogging,
        path: join(DIRECTORIES.dockerBuildContext, "logging.properties"),
      },
    ];

    await Promise.all(
      downloads.map(async ({ url, path }) => {
        await this.downloadFile(url, path);
        this.stats.dockerFilesFetched++;
        console.log(`   ✓ Downloaded ${path}`);
      })
    );
  }

  private async downloadFile(url: string, filePath: string): Promise<void> {
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`Failed to download ${url}: ${response.statusText}`);
    }

    const content = await response.text();
    await writeFile(filePath, content, "utf-8");
  }

  private async compileConfigWithDocker(
    envVars: Record<string, string>
  ): Promise<void> {
    console.log("\n🐳 Compiling config with Docker...");

    const tempDir = DIRECTORIES.tempWorkDir;
    await mkdir(tempDir, { recursive: true });

    // Create environment file for Docker
    const envContent = Object.entries(envVars)
      .map(([key, value]) => `${key}=${value}`)
      .join("\n");

    const envFile = join(tempDir, ".env");
    await writeFile(envFile, envContent);

    // Copy the template file to temp directory
    const templatePath = join(DIRECTORIES.dockerBuildContext, "jvb.conf");
    const tempTemplatePath = join(tempDir, "jvb.conf.template");
    const compiledPath = join(tempDir, "jvb.conf.compiled");

    const templateContent = await readFile(templatePath, "utf-8");
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

      // Verify the compiled file was created
      if (!(await exists(compiledPath))) {
        throw new Error("Compiled config file was not created");
      }

      this.stats.configCompiled = true;
      console.log("   ✅ Config compiled successfully");
    } catch (error) {
      console.error("   ❌ Docker compilation failed:", error);
      throw new Error(
        "Failed to compile config with Docker. This is required for the script to work correctly."
      );
    }
  }

  private async compareAndUpdateConfig(): Promise<void> {
    console.log("\n🔍 Comparing configs and updating custom config...");

    const compiledConfigPath = join(
      DIRECTORIES.tempWorkDir,
      "jvb.conf.compiled"
    );
    const customConfigPath = "./custom-jvb.conf";

    try {
      const compiledContent = await readFile(compiledConfigPath, "utf-8");
      const customContent = await readFile(customConfigPath, "utf-8");

      // Parse both configs using HOCON parser
      const compiledConfig = await this.parseHoconConfig(compiledContent);
      const customConfig = await this.parseHoconConfig(customContent);

      // Find differences between configs
      const differences = this.compareConfigs(compiledConfig, customConfig);
      const missingKeys = differences.filter((diff) => diff.isMissing);
      const typeMismatches = differences.filter((diff) => !diff.isMissing);

      this.stats.missingKeys = missingKeys.map((k) => k.path);
      this.stats.typeMismatches = typeMismatches.map(
        (diff) =>
          `${diff.path}: expected ${diff.expectedType} but got ${diff.actualType}`
      );

      if (missingKeys.length > 0) {
        console.log("   ⚠️  Found missing keys in custom config:");
        missingKeys.forEach((key) => console.log(`      - ${key.path}`));

        // Update the custom config with missing keys
        await this.updateCustomConfigWithMissingKeys(
          customContent,
          missingKeys
        );
        this.stats.customConfigUpdated = true;
      } else {
        console.log(
          "   ✅ All keys from compiled config are present in custom config"
        );
      }

      if (typeMismatches.length > 0) {
        console.log("   ⚠️  Found type mismatches:");
        typeMismatches.forEach((diff) =>
          console.log(
            `      - ${diff.path}: expected ${diff.expectedType}, got ${diff.actualType}`
          )
        );
      }
    } catch (error) {
      console.error("   ❌ Error comparing configs:", error);
      throw error;
    }
  }

  private async parseHoconConfig(configContent: string): Promise<any> {
    try {
      return await hocon.parse({ text: configContent, strict: false });
    } catch (error) {
      console.error("   ❌ Failed to parse HOCON config:", error);
      throw new Error(`HOCON parsing failed: ${error}`);
    }
  }

  private compareConfigs(
    compiledConfig: any,
    customConfig: any,
    currentPath: string = ""
  ): ConfigDifference[] {
    const differences: ConfigDifference[] = [];

    const flattenConfig = (
      obj: any,
      prefix: string = ""
    ): Map<string, { value: any; type: string }> => {
      const flattened = new Map();

      for (const [key, value] of Object.entries(obj)) {
        const fullPath = prefix ? `${prefix}.${key}` : key;

        if (
          value !== null &&
          typeof value === "object" &&
          !Array.isArray(value)
        ) {
          // Recursively flatten nested objects
          const nested = this.flattenConfig(value, fullPath);
          for (const [nestedPath, nestedValue] of nested) {
            flattened.set(nestedPath, nestedValue);
          }
        } else {
          flattened.set(fullPath, {
            value,
            type: this.getHoconValueType(value),
          });
        }
      }

      return flattened;
    };

    const compiledFlat = flattenConfig(compiledConfig);
    const customFlat = flattenConfig(customConfig);

    // Debug output
    if (process.env.DEBUG_CONFIG) {
      console.log(
        "   🔍 Debug: Compiled config keys:",
        Array.from(compiledFlat.keys()).slice(0, 10)
      );
      console.log(
        "   🔍 Debug: Custom config keys:",
        Array.from(customFlat.keys()).slice(0, 10)
      );
    }

    // Check for missing keys and type mismatches
    for (const [path, compiledEntry] of compiledFlat) {
      const customEntry = customFlat.get(path);

      if (!customEntry) {
        // Key is missing
        differences.push({
          path,
          expectedValue: compiledEntry.value,
          expectedType: compiledEntry.type,
          isMissing: true,
        });
      } else if (compiledEntry.type !== customEntry.type) {
        // Type mismatch
        differences.push({
          path,
          expectedValue: compiledEntry.value,
          expectedType: compiledEntry.type,
          actualValue: customEntry.value,
          actualType: customEntry.type,
          isMissing: false,
        });
      }
    }

    return differences;
  }

  private flattenConfig(
    obj: any,
    prefix: string = ""
  ): Map<string, { value: any; type: string }> {
    const flattened = new Map();

    for (const [key, value] of Object.entries(obj)) {
      const fullPath = prefix ? `${prefix}.${key}` : key;

      if (
        value !== null &&
        typeof value === "object" &&
        !Array.isArray(value)
      ) {
        // Recursively flatten nested objects
        const nested = this.flattenConfig(value, fullPath);
        for (const [nestedPath, nestedValue] of nested) {
          flattened.set(nestedPath, nestedValue);
        }
      } else {
        flattened.set(fullPath, {
          value,
          type: this.getHoconValueType(value),
        });
      }
    }

    return flattened;
  }

  private getHoconValueType(value: any): string {
    if (value === null) return "null";
    if (typeof value === "boolean") return "boolean";
    if (typeof value === "number") return "number";
    if (Array.isArray(value)) return "array";
    if (typeof value === "object") return "object";
    return "string";
  }

  private async updateCustomConfigWithMissingKeys(
    customContent: string,
    missingKeys: ConfigDifference[]
  ): Promise<void> {
    if (missingKeys.length === 0) return;

    console.log("   📝 Adding missing keys with default values...");

    // Check for commented-out keys
    const commentedKeys = this.findCommentedKeys(customContent);
    const actualMissingKeys = missingKeys.filter(
      (key) => !commentedKeys.has(key.path)
    );
    const commentedMissingKeys = missingKeys.filter((key) =>
      commentedKeys.has(key.path)
    );

    if (commentedMissingKeys.length > 0) {
      console.log(
        `   ℹ️  Found ${commentedMissingKeys.length} keys that are commented out:`
      );
      commentedMissingKeys.forEach((key) =>
        console.log(`      - ${key.path} (commented out)`)
      );
    }

    // Filter out problematic keys, but be more intelligent about it
    const filteredKeys = actualMissingKeys.filter((key) => {
      const pathParts = key.path.split(".");
      const lastPart = pathParts[pathParts.length - 1];

      // Allow certain known configuration keys even if they might be arrays
      const allowedArrayKeys = [
        "static-mappings",
        "addresses",
        "servers",
        "domains",
      ];
      if (allowedArrayKeys.includes(lastPart)) {
        return true;
      }

      // Skip keys that are likely array indices or complex nested structures
      return !pathParts.some(
        (part) =>
          part.match(/^\d+$/) || // Array indices like "0", "1", etc.
          part.includes("[") ||
          part.includes("]")
      );
    });

    if (filteredKeys.length === 0) {
      console.log(
        "   ℹ️  All missing keys are complex structures or commented out, skipping automatic addition"
      );
      return;
    }

    // Debug output
    if (process.env.DEBUG_CONFIG) {
      console.log(
        "   🔍 Debug: Filtered keys to add:",
        filteredKeys.map((k) => `${k.path} = ${k.expectedValue}`)
      );
    }

    // Try to parse and merge configs using HOCON parser for better structure preservation
    try {
      const currentConfig = await this.parseHoconConfig(customContent);

      // Add missing keys to the current config
      for (const missingKey of filteredKeys) {
        this.setNestedValue(
          currentConfig,
          missingKey.path,
          missingKey.expectedValue
        );
      }

      // Convert back to HOCON format and append to original content
      const timestamp = new Date().toISOString();
      let updatedContent = customContent;

      updatedContent += `\n\n# Missing keys added during config sync (${timestamp})\n`;

      // Create nested structure for each missing key
      const keysBySection = this.groupKeysBySection(filteredKeys);

      for (const [sectionPath, keys] of keysBySection) {
        updatedContent += this.createNestedConfigSection(sectionPath, keys);
      }

      // Write the updated config
      await writeFile("./custom-jvb.conf", updatedContent);

      console.log(
        `   ✅ Added ${filteredKeys.length} missing keys with proper structure`
      );

      if (missingKeys.length > filteredKeys.length) {
        console.log(
          `   ℹ️  Skipped ${
            missingKeys.length - filteredKeys.length
          } complex keys`
        );
      }
    } catch (error) {
      console.error(
        "   ⚠️  Failed to merge configs intelligently, falling back to simple append"
      );
      await this.fallbackConfigUpdate(customContent, filteredKeys);
    }
  }

  private findCommentedKeys(content: string): Set<string> {
    const commentedKeys = new Set<string>();
    const lines = content.split("\n");

    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed.startsWith("#") || trimmed.startsWith("//")) {
        // Try to extract key from commented line
        const match = trimmed.match(/^#\s*([a-zA-Z0-9._-]+)\s*=/);
        if (match) {
          commentedKeys.add(match[1]);
        }
      }
    }

    return commentedKeys;
  }

  private setNestedValue(obj: any, path: string, value: any): void {
    const keys = path.split(".");
    let current = obj;

    for (let i = 0; i < keys.length - 1; i++) {
      if (!(keys[i] in current)) {
        current[keys[i]] = {};
      }
      current = current[keys[i]];
    }

    current[keys[keys.length - 1]] = value;
  }

  private groupKeysBySection(
    keys: ConfigDifference[]
  ): Map<string, ConfigDifference[]> {
    const keysBySection = new Map<string, ConfigDifference[]>();

    for (const key of keys) {
      const pathParts = key.path.split(".");
      const section = pathParts.slice(0, -1).join(".");

      if (!keysBySection.has(section)) {
        keysBySection.set(section, []);
      }
      keysBySection.get(section)!.push(key);
    }

    return keysBySection;
  }

  private createNestedConfigSection(
    sectionPath: string,
    keys: ConfigDifference[]
  ): string {
    if (keys.length === 0) return "";

    const sectionParts = sectionPath
      .split(".")
      .filter((part) => part.length > 0);
    let result = `\n# Added missing keys for ${sectionPath || "root"}\n`;

    // Create nested structure
    let indent = "";

    // Open nested sections
    for (const section of sectionParts) {
      result += `${indent}${section} {\n`;
      indent += "    ";
    }

    // Add the missing keys
    for (const key of keys) {
      const keyName = key.path.split(".").pop();
      const formattedValue = this.formatHoconValue(key.expectedValue);
      result += `${indent}${keyName} = ${formattedValue}\n`;
    }

    // Close nested sections
    for (let i = sectionParts.length - 1; i >= 0; i--) {
      indent = "    ".repeat(i);
      result += `${indent}}\n`;
    }

    return result;
  }

  private formatHoconValue(value: any): string {
    if (value === null) return "null";
    if (typeof value === "boolean") return value.toString();
    if (typeof value === "number") return value.toString();
    if (Array.isArray(value)) {
      if (value.length === 0) return "[]";

      // For arrays of objects, format each object properly
      const formattedItems = value.map((item) => {
        if (typeof item === "object" && item !== null) {
          // Format objects with proper HOCON syntax
          const entries = Object.entries(item).map(
            ([k, v]) => `${k}: ${this.formatHoconValue(v)}`
          );
          return `{ ${entries.join(", ")} }`;
        }
        return this.formatHoconValue(item);
      });

      if (formattedItems.length === 1 && typeof value[0] === "object") {
        // Single object array - format on multiple lines for readability
        return `[\n        ${formattedItems[0]}\n    ]`;
      }

      return `[${formattedItems.join(", ")}]`;
    }
    if (typeof value === "object") {
      // Format objects with proper HOCON syntax
      const entries = Object.entries(value).map(
        ([k, v]) => `${k}: ${this.formatHoconValue(v)}`
      );
      return `{ ${entries.join(", ")} }`;
    }

    // String values - quote if necessary
    const str = value.toString();
    if (
      str.includes(" ") ||
      str.includes('"') ||
      str.includes("'") ||
      str.includes(":")
    ) {
      return `"${str.replace(/"/g, '\\"')}"`;
    }
    return str;
  }

  private async fallbackConfigUpdate(
    customContent: string,
    keys: ConfigDifference[]
  ): Promise<void> {
    const timestamp = new Date().toISOString();
    let updatedContent = customContent;

    updatedContent += `\n\n# Missing keys added during config sync (${timestamp}) - Fallback mode\n`;

    for (const key of keys) {
      const formattedValue = this.formatHoconValue(key.expectedValue);
      updatedContent += `# ${key.path} = ${formattedValue}\n`;
    }

    await writeFile("./custom-jvb.conf", updatedContent);
    console.log(
      `   ⚠️  Added ${keys.length} keys as comments for manual review`
    );
  }

  private printStats(): void {
    console.log("\n📊 Summary of changes:");
    console.log("════════════════════════════════════════");
    console.log(`   Environment variables loaded: ${this.stats.envVarsLoaded}`);
    console.log(
      `   Reference files fetched: ${this.stats.referenceFilesFetched}`
    );
    console.log(
      `   Docker build files fetched: ${this.stats.dockerFilesFetched}`
    );
    console.log(
      `   Config compiled with Docker: ${
        this.stats.configCompiled ? "✅" : "❌"
      }`
    );
    console.log(`   Missing keys found: ${this.stats.missingKeys.length}`);
    console.log(
      `   Type mismatches found: ${this.stats.typeMismatches.length}`
    );
    console.log(
      `   Custom config updated: ${
        this.stats.customConfigUpdated ? "✅" : "❌"
      }`
    );

    if (this.stats.missingKeys.length > 0) {
      console.log("\n   Missing keys added:");
      this.stats.missingKeys.forEach((key) => console.log(`     • ${key}`));
    }

    if (this.stats.typeMismatches.length > 0) {
      console.log("\n   Type mismatches found:");
      this.stats.typeMismatches.forEach((mismatch) =>
        console.log(`     • ${mismatch}`)
      );
    }

    console.log("\n✨ Config update process completed successfully!");
  }

  private async cleanup(): Promise<void> {
    try {
      const tempDir = DIRECTORIES.tempWorkDir;
      if (await exists(tempDir)) {
        await rm(tempDir, { recursive: true, force: true });
        console.log("🧹 Cleaned up temporary files");
      }
    } catch (error) {
      // Ignore cleanup errors, but log them
      console.warn("⚠️  Warning: Failed to cleanup temporary files:", error);
    }
  }
}

// Main execution
if (import.meta.main) {
  const fetcher = new ConfigFetcher();

  // Ensure cleanup on unexpected exit
  process.on("SIGINT", async () => {
    console.log("\n🛑 Process interrupted, cleaning up...");
    await fetcher["cleanup"]();
    process.exit(0);
  });

  process.on("SIGTERM", async () => {
    console.log("\n🛑 Process terminated, cleaning up...");
    await fetcher["cleanup"]();
    process.exit(0);
  });

  await fetcher.run();
}
