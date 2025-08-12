#!/usr/bin/env bun

import { rm, exists, mkdir } from "fs/promises";
import { dirname, join, resolve } from "path";
import { downloadFiles } from "./downloader.js";
import { loadEnvironmentVariables, compileConfigWithDocker } from "./compiler.js";
import { ConfigComparator } from "./comparator.js";
import type { DownloadTarget } from "./types.js";
import { fileURLToPath } from "url";


// Get the absolute path to this file
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Configuration constants
const GITHUB_URL = "https://raw.githubusercontent.com/jitsi/";
const PATHS = {
  jvbReference: join(__dirname, "../videobridge/reference/"),
  jicofoReference: join(__dirname, "../config/jicofoReference/"),
  prosodyReference: join(__dirname, "../config/prosodyReference/"),
  buildDir: resolve(__dirname, "./build"),
  envFile: join(__dirname, "../.env"),
  customConfig: join(__dirname, "./custom-jvb.conf"),

  composeJvb: "",
  composeProsody: "",

  compiledJvbConfig: "",
  compiledJicofoConfig: "",
  compiledProsodyConfig: "",
};

PATHS.composeJvb = join(PATHS.jvbReference, "../compose.jvb.yml");
PATHS.composeProsody = join(PATHS.prosodyReference, "../compose.yml");
PATHS.compiledJvbConfig = join(PATHS.buildDir, "jvb.conf.compiled");
PATHS.compiledJicofoConfig = join(PATHS.buildDir, "jicofo.conf.compiled");
PATHS.compiledProsodyConfig = join(PATHS.buildDir, "prosody.conf.compiled");

const jvbReferenceTargets: DownloadTarget[] = [
  {
    url: GITHUB_URL + "jitsi-videobridge/master/jvb/src/main/resources/reference.conf",
    path: join(PATHS.jvbReference, "jvb-reference.conf"),
  },
  {
    url: GITHUB_URL + "ice4j/master/src/main/resources/reference.conf",
    path: join(PATHS.jvbReference, "ice4j-reference.conf"),
  },
  {
    url: GITHUB_URL + "docker-jitsi-meet/master/jvb/rootfs/etc/cont-init.d/10-config",
    path: join(PATHS.jvbReference, "10-config"),
  },
  {
    url: GITHUB_URL + "docker-jitsi-meet/master/jvb/rootfs/defaults/jvb.conf",
    path: join(PATHS.jvbReference, "jvb.conf"),
  },
  {
    url: GITHUB_URL + "docker-jitsi-meet/master/jvb/rootfs/defaults/logging.properties",
    path: join(PATHS.jvbReference, "logging.properties"),
  },
  {
    url:
      GITHUB_URL +
      "jitsi-videobridge/master/jitsi-media-transform/src/main/resources/reference.conf",
    path: join(PATHS.jvbReference, "jitsi-media-transform-reference.conf"),
  },
];

const jicofoReferenceTargets: DownloadTarget[] = [
  {
    url: GITHUB_URL + "jicofo/master/jicofo-selector/src/main/resources/reference.conf",
    path: join(PATHS.jicofoReference, "jicofo-reference.conf"),
  },
  {
    url: GITHUB_URL + "docker-jitsi-meet/master/jicofo/rootfs/etc/cont-init.d/10-config",
    path: join(PATHS.jicofoReference, "10-config"),
  },
  {
    url: GITHUB_URL + "docker-jitsi-meet/master/jicofo/rootfs/defaults/jicofo.conf",
    path: join(PATHS.jicofoReference, "jicofo.conf"),
  },
  {
    url: GITHUB_URL + "docker-jitsi-meet/master/jicofo/rootfs/defaults/logging.properties",
    path: join(PATHS.jicofoReference, "logging.properties"),
  },
];

const prosodyReferenceTargets: DownloadTarget[] = [
  {
    url: GITHUB_URL + "docker-jitsi-meet/master/prosody/rootfs/etc/cont-init.d/10-config",
    path: join(PATHS.prosodyReference, "10-config"),
  },
  {
    url: GITHUB_URL + "docker-jitsi-meet/master/prosody/rootfs/defaults/prosody.cfg.lua",
    path: join(PATHS.prosodyReference, "prosody.cfg.lua"),
  },
  {
    url: GITHUB_URL + "docker-jitsi-meet/master/prosody/rootfs/defaults/conf.d/brewery.cfg.lua",
    path: join(PATHS.prosodyReference, "brewery.cfg.lua"),
  },
  {
    url: GITHUB_URL + "docker-jitsi-meet/master/prosody/rootfs/defaults/conf.d/jitsi-meet.cfg.lua",
    path: join(PATHS.prosodyReference, "jitsi-meet.cfg.lua"),
  },
  {
    url: GITHUB_URL + "docker-jitsi-meet/master/prosody/rootfs/defaults/conf.d/visitors.cfg.lua",
    path: join(PATHS.prosodyReference, "visitors.cfg.lua"),
  },
];

class ConfigSyncManager {
  private comparator = new ConfigComparator();

  async run(): Promise<void> {
    console.log("🚀 Starting config update process...\n");

    try {
      // Step 0: Create build directory if needed
      await mkdir(PATHS.buildDir, { recursive: true });

      // Step 1: Download all reference and build context files
      await this.downloadResources();

      // Step 2: Load environment variables and compile config
      await this.compileConfig();

      // Step 3: Compare and update custom config
      // await this.compareConfigs();

      console.log("\n✨ Config update process completed successfully!");
    } catch (error) {
      console.error("❌ Error during config update:", error);
      throw error;
    } finally {
      // Always cleanup temp files
      // await this.cleanup();
    }
  }

  private async downloadResources(): Promise<void> {
    console.log("📥 Fetching JVB reference configs...");
    await downloadFiles(jvbReferenceTargets);

    console.log("\n📥 Fetching Jicofo reference configs...");
    await downloadFiles(jicofoReferenceTargets);

    console.log("\n📥 Fetching Prosody reference configs...");
    await downloadFiles(prosodyReferenceTargets);
  }

  private async compileConfig(): Promise<void> {
    console.log("\n🔧 Loading environment variables and compiling config...");

    async function compileWithEnv(
      composeFile: string,
      containerName: string,
      templatePath: string,
      outputPath: string,
    ) {
      // Load environment variables from compose file and .env
      const envVars = await loadEnvironmentVariables(
        containerName,
        composeFile,
        PATHS.envFile
      );

      // Compile config using Docker
      await compileConfigWithDocker({
        envVars,
        templatePath,
        outputPath,
      });
    }

    await compileWithEnv(
      PATHS.composeJvb,
      "jvb",
      join(PATHS.jvbReference, "jvb.conf"),
      PATHS.compiledJvbConfig,
    );
    await compileWithEnv(
      PATHS.composeProsody,
      "prosody",
      join(PATHS.prosodyReference, "prosody.cfg.lua"),
      PATHS.compiledProsodyConfig,
    );
    await compileWithEnv(
      PATHS.composeProsody,
      "prosody",
      join(PATHS.prosodyReference, "jitsi-meet.cfg.lua"),
      PATHS.compiledProsodyConfig + ".jitsi-meet",
    );
    await compileWithEnv(
      PATHS.composeProsody,
      "jicofo",
      join(PATHS.jicofoReference, "jicofo.conf"),
      PATHS.compiledJicofoConfig,
    );
  }

  private async compareConfigs(): Promise<void> {
    // Compare compiled config with custom config and update if needed
    await this.comparator.compareAndUpdateConfig({
      compiledConfigPath: PATHS.compiledJvbConfig,
      customConfigPath: PATHS.customConfig,
      updateConfig: true,
    });
  }

  private async cleanup(): Promise<void> {
    try {
      const tempDir = PATHS.buildDir;
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
  const manager = new ConfigSyncManager();

  // Ensure cleanup on unexpected exit
  const handleExit = async () => {
    console.log("\n🛑 Process interrupted, cleaning up...");
    await manager["cleanup"]();
    process.exit(0);
  };

  process.on("SIGINT", handleExit);
  process.on("SIGTERM", handleExit);

  try {
    await manager.run();
  } catch (error) {
    console.error("\n❌ Process failed:", error);
    process.exit(1);
  }
}
