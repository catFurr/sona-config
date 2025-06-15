import { mkdir, writeFile, exists } from "fs/promises";
import { dirname } from "path";
import type { DownloadTarget } from "./types.js";


async function ensureDirectories(targets: DownloadTarget[]): Promise<void> {
    const directories = new Set(targets.map((target) => dirname(target.path)));

    await Promise.all(
      Array.from(directories).map(async (dir) => {
        if (!(await exists(dir))) {
          await mkdir(dir, { recursive: true });
          console.log(`   📁 Created directory ${dir}`);
        }
      })
    );
}

async function downloadFile(url: string, filePath: string): Promise<void> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to download ${url}: ${response.statusText}`);
  }

  const content = await response.text();
  await writeFile(filePath, content, "utf-8");
}

export async function downloadFiles(targets: DownloadTarget[]): Promise<void> {
  console.log(`📥 Fetching ${targets.length} files...`);

  // Ensure all target directories exist
  await ensureDirectories(targets);

  // Download all files in parallel
  await Promise.all(
    targets.map(async (target) => {
      await downloadFile(target.url, target.path);
      console.log(`   ✓ Downloaded ${target.path}`);
    })
  );
}
