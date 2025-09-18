// This script generates the documentation for the backend.

// For now we are only interested in events.

// 1. Scan the prosody-plugins folder for list of all the files
// 2. For each module (mod_xyz.lua) scan for the following:
// - fire event
// - hook event (even global hooks!)
// - anything else related to events
// Save this information to a markdown file in the doc folder
// related to that event.
// 3. Update the doc/events.md file with the new information.
// This file contains list of all events, with short summary such as:
// - number of places its fired
// - number of places its hooked
// - etc

import {
  readdirSync,
  readFileSync,
  writeFileSync,
  existsSync,
  mkdirSync,
} from "fs";
import { join, relative, extname } from "path";

interface EventInfo {
  name: string;
  type: "hook" | "hook_global" | "fire" | "fire_global";
  file: string;
  line: number;
  context: string;
  description?: string;
}

interface PluginInfo {
  name: string;
  file: string;
  events: EventInfo[];
  description?: string;
}

interface EventSummary {
  name: string;
  fireCount: number;
  hookCount: number;
  files: string[];
  description?: string;
}

class DocsGenerator {
  private plugins: PluginInfo[] = [];
  private events: Map<string, EventSummary> = new Map();
  private prosodyPluginsPath: string;
  private docsPath: string;

  constructor() {
    this.prosodyPluginsPath = join(process.cwd(), "prosody-plugins");
    this.docsPath = join(process.cwd(), "doc");

    // Ensure doc directory exists
    if (!existsSync(this.docsPath)) {
      mkdirSync(this.docsPath, { recursive: true });
    }
  }

  // Scan for Lua files in the prosody-plugins directory
  private scanLuaFiles(dir: string): string[] {
    const files: string[] = [];

    const items = readdirSync(dir, { withFileTypes: true });

    for (const item of items) {
      const fullPath = join(dir, item.name);

      if (item.isDirectory()) {
        files.push(...this.scanLuaFiles(fullPath));
      } else if (item.isFile() && extname(item.name) === ".lua") {
        files.push(fullPath);
      }
    }

    return files;
  }

  // Parse a single Lua file for events
  private parseFile(filePath: string): PluginInfo {
    const content = readFileSync(filePath, "utf-8");
    const lines = content.split("\n");
    const events: EventInfo[] = [];
    const fileName = relative(this.prosodyPluginsPath, filePath);

    // Extract plugin name from filename
    const pluginName = fileName.includes("mod_")
      ? fileName.split("/").pop()?.replace(".lua", "") || fileName
      : fileName;

    // Patterns to match different event types
    const patterns = [
      // module:hook_global("event-name", function)
      {
        regex: /module:hook_global\s*\(\s*["']([^"']+)["']\s*,/g,
        type: "hook_global" as const,
      },
      // module:hook("event-name", function)
      {
        regex: /module:hook\s*\(\s*["']([^"']+)["']\s*,/g,
        type: "hook" as const,
      },
      // prosody.events.fire_event('event-name', {...})
      {
        regex: /prosody\.events\.fire_event\s*\(\s*["']([^"']+)["']\s*,/g,
        type: "fire_global" as const,
      },
      // fire_event("event-name", {...})
      {
        regex: /(?:^|[^a-zA-Z_.])fire_event\s*\(\s*["']([^"']+)["']\s*,/g,
        type: "fire" as const,
      },
      // module:fire_event("event-name", {...})
      {
        regex: /module:fire_event\s*\(\s*["']([^"']+)["']\s*,/g,
        type: "fire" as const,
      },
    ];

    // Parse each line
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];

      for (const pattern of patterns) {
        let match;
        pattern.regex.lastIndex = 0; // Reset regex

        while ((match = pattern.regex.exec(line)) !== null) {
          const eventName = match[1];
          const context = this.getContext(lines, i, 2);

          events.push({
            name: eventName,
            type: pattern.type,
            file: fileName,
            line: i + 1,
            context: context,
            description: this.extractDescription(lines, i),
          });
        }
      }
    }

    // Try to extract plugin description from comments at the top
    const description = this.extractPluginDescription(lines);

    return {
      name: pluginName,
      file: fileName,
      events,
      description,
    };
  }

  // Get context around a line (for better documentation)
  private getContext(
    lines: string[],
    lineIndex: number,
    contextLines: number = 2
  ): string {
    const start = Math.max(0, lineIndex - contextLines);
    const end = Math.min(lines.length, lineIndex + contextLines + 1);

    return lines
      .slice(start, end)
      .map((line, i) => {
        const actualLineNum = start + i + 1;
        const marker = actualLineNum === lineIndex + 1 ? ">" : " ";
        return `${marker} ${actualLineNum.toString().padStart(3)}: ${line}`;
      })
      .join("\n");
  }

  // Extract description from comments
  private extractDescription(
    lines: string[],
    lineIndex: number
  ): string | undefined {
    // Look for comments above the line
    for (let i = lineIndex - 1; i >= 0; i--) {
      const line = lines[i].trim();
      if (line.startsWith("--")) {
        return line.replace(/^--+\s*/, "");
      } else if (line === "") {
        continue;
      } else {
        break;
      }
    }
    return undefined;
  }

  // Extract plugin description from top comments
  private extractPluginDescription(lines: string[]): string | undefined {
    const descriptions: string[] = [];

    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed.startsWith("--")) {
        descriptions.push(trimmed.replace(/^--+\s*/, ""));
      } else if (trimmed === "") {
        continue;
      } else {
        break;
      }
    }

    return descriptions.length > 0 ? descriptions.join(" ") : undefined;
  }

  // Aggregate events across all plugins
  private aggregateEvents() {
    this.events.clear();

    for (const plugin of this.plugins) {
      for (const event of plugin.events) {
        if (!this.events.has(event.name)) {
          this.events.set(event.name, {
            name: event.name,
            fireCount: 0,
            hookCount: 0,
            files: [],
            description: event.description,
          });
        }

        const summary = this.events.get(event.name)!;

        if (event.type === "fire" || event.type === "fire_global") {
          summary.fireCount++;
        } else {
          summary.hookCount++;
        }

        if (!summary.files.includes(plugin.file)) {
          summary.files.push(plugin.file);
        }

        // Update description if we don't have one
        if (!summary.description && event.description) {
          summary.description = event.description;
        }
      }
    }
  }

  // Generate individual event documentation
  private generateEventDocs() {
    const eventsDir = join(this.docsPath, "events");
    if (!existsSync(eventsDir)) {
      mkdirSync(eventsDir, { recursive: true });
    }

    for (const [eventName, eventSummary] of this.events) {
      const eventDoc = this.generateEventMarkdown(eventName, eventSummary);
      const eventFile = join(
        eventsDir,
        `${eventName.replace(/[^a-zA-Z0-9-]/g, "-")}.md`
      );
      writeFileSync(eventFile, eventDoc);
    }
  }

  // Generate markdown for a single event
  private generateEventMarkdown(
    eventName: string,
    eventSummary: EventSummary
  ): string {
    const markdown = [];

    markdown.push(`# Event: ${eventName}\n`);

    if (eventSummary.description) {
      markdown.push(`## Description\n`);
      markdown.push(`${eventSummary.description}\n`);
    }

    markdown.push(`## Summary\n`);
    markdown.push(`- **Fired**: ${eventSummary.fireCount} times`);
    markdown.push(`- **Hooked**: ${eventSummary.hookCount} times`);
    markdown.push(`- **Files involved**: ${eventSummary.files.length}\n`);

    // Group occurrences by file
    const occurrencesByFile = new Map<string, EventInfo[]>();

    for (const plugin of this.plugins) {
      for (const event of plugin.events) {
        if (event.name === eventName) {
          if (!occurrencesByFile.has(plugin.file)) {
            occurrencesByFile.set(plugin.file, []);
          }
          occurrencesByFile.get(plugin.file)!.push(event);
        }
      }
    }

    markdown.push(`## Occurrences\n`);

    for (const [file, events] of occurrencesByFile) {
      markdown.push(`### ${file}\n`);

      for (const event of events) {
        markdown.push(`**${event.type.toUpperCase()}** (line ${event.line}):`);
        if (event.description) {
          markdown.push(`*${event.description}*`);
        }
        markdown.push("```lua");
        markdown.push(event.context);
        markdown.push("```\n");
      }
    }

    return markdown.join("\n");
  }

  // Generate overview events.md file
  private generateOverview() {
    const markdown = [];

    markdown.push("# Prosody Events Documentation\n");
    markdown.push(
      "This documentation was auto-generated from the Prosody plugins.\n"
    );

    // Plugin summary
    markdown.push("## Plugins Overview\n");
    markdown.push("| Plugin | Events | Description |");
    markdown.push("|--------|---------|-------------|");

    for (const plugin of this.plugins) {
      const eventCount = plugin.events.length;
      const description = plugin.description || "";
      markdown.push(`| ${plugin.name} | ${eventCount} | ${description} |`);
    }

    markdown.push("\n## Events Summary\n");
    markdown.push("| Event | Fired | Hooked | Files | Description |");
    markdown.push("|-------|-------|--------|-------|-------------|");

    // Sort events by name
    const sortedEvents = Array.from(this.events.entries()).sort((a, b) =>
      a[0].localeCompare(b[0])
    );

    for (const [eventName, eventSummary] of sortedEvents) {
      const description = eventSummary.description || "";
      const eventLink = `[${eventName}](events/${eventName.replace(
        /[^a-zA-Z0-9-]/g,
        "-"
      )}.md)`;
      markdown.push(
        `| ${eventLink} | ${eventSummary.fireCount} | ${eventSummary.hookCount} | ${eventSummary.files.length} | ${description} |`
      );
    }

    // Statistics
    markdown.push("## Statistics\n");
    markdown.push(`- **Total Plugins**: ${this.plugins.length}`);
    markdown.push(`- **Total Events**: ${this.events.size}`);
    markdown.push(
      `- **Total Event Occurrences**: ${this.plugins.reduce(
        (sum, p) => sum + p.events.length,
        0
      )}`
    );

    const totalFired = Array.from(this.events.values()).reduce(
      (sum, e) => sum + e.fireCount,
      0
    );
    const totalHooked = Array.from(this.events.values()).reduce(
      (sum, e) => sum + e.hookCount,
      0
    );

    markdown.push(`- **Total Fire Events**: ${totalFired}`);
    markdown.push(`- **Total Hook Events**: ${totalHooked}`);

    const overviewFile = join(this.docsPath, "events.md");
    writeFileSync(overviewFile, markdown.join("\n"));
  }

  // Main generation function
  public async generate(): Promise<void> {
    console.log("🔍 Scanning Prosody plugins...");

    // Find all Lua files
    const luaFiles = this.scanLuaFiles(this.prosodyPluginsPath);
    console.log(`Found ${luaFiles.length} Lua files`);

    // Parse each file
    for (const file of luaFiles) {
      console.log(`📄 Processing ${relative(this.prosodyPluginsPath, file)}`);
      const pluginInfo = this.parseFile(file);
      this.plugins.push(pluginInfo);
    }

    // Aggregate events
    console.log("🔄 Aggregating events...");
    this.aggregateEvents();

    // Generate documentation
    console.log("📝 Generating documentation...");
    this.generateEventDocs();
    this.generateOverview();

    console.log("✅ Documentation generated successfully!");
    console.log(`📂 Documentation location: ${this.docsPath}`);
    console.log(
      `📊 Generated docs for ${this.plugins.length} plugins and ${this.events.size} events`
    );
  }
}

// Run the generator
const generator = new DocsGenerator();
generator.generate().catch(console.error);
