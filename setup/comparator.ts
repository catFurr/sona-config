import { readFile, writeFile } from "fs/promises";
import * as hocon from "@pushcorn/hocon-parser";
import type { ConfigDifference, ComparisonOptions } from "./types.js";

// Type declaration for hocon-parser to fix linter errors
declare module "@pushcorn/hocon-parser" {
  export function parse(options: {
    text: string;
    strict?: boolean;
  }): Promise<any>;
}

export class ConfigComparator {
  async compareAndUpdateConfig(options: ComparisonOptions): Promise<void> {
    console.log("🔍 Comparing configs and updating custom config...");

    try {
      const compiledContent = await readFile(
        options.compiledConfigPath,
        "utf-8"
      );
      const customContent = await readFile(options.customConfigPath, "utf-8");

      // Parse both configs using HOCON parser
      const compiledConfig = await this.parseHoconConfig(compiledContent);
      const customConfig = await this.parseHoconConfig(customContent);

      // Find differences between configs
      const differences = this.compareConfigs(compiledConfig, customConfig);
      const missingKeys = differences.filter((diff) => diff.isMissing);
      const typeMismatches = differences.filter((diff) => !diff.isMissing);

      console.log(`   📊 Missing keys found: ${missingKeys.length}`);
      console.log(`   📊 Type mismatches found: ${typeMismatches.length}`);

      if (missingKeys.length > 0) {
        console.log("   ⚠️  Found missing keys in custom config:");
        missingKeys.forEach((key) => console.log(`      - ${key.path}`));

        if (options.updateConfig) {
          await this.updateCustomConfigWithMissingKeys(
            customContent,
            missingKeys,
            options.customConfigPath
          );
        }
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
    customConfig: any
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
          const nested = flattenConfig(value, fullPath);
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
    missingKeys: ConfigDifference[],
    customConfigPath: string
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

    // Filter out problematic keys
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
      if (lastPart && allowedArrayKeys.includes(lastPart)) {
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

    try {
      // Create nested structure for each missing key
      const timestamp = new Date().toISOString();
      let updatedContent = customContent;

      updatedContent += `\n\n# Missing keys added during config sync (${timestamp})\n`;

      const keysBySection = this.groupKeysBySection(filteredKeys);
      for (const [sectionPath, keys] of keysBySection) {
        updatedContent += this.createNestedConfigSection(sectionPath, keys);
      }

      await writeFile(customConfigPath, updatedContent);
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
      console.error("   ⚠️  Failed to update config:", error);
      throw error;
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
        if (match && match[1]) {
          commentedKeys.add(match[1]);
        }
      }
    }

    return commentedKeys;
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
      const pathParts = key.path.split(".");
      const keyName = pathParts[pathParts.length - 1];
      if (keyName) {
        const formattedValue = this.formatHoconValue(key.expectedValue);
        result += `${indent}${keyName} = ${formattedValue}\n`;
      }
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
}
