import fs from "node:fs";
import path from "node:path";
import type { StudioOutputMessage } from "./ipc/messages.js";

interface SourcemapNode {
  name: string;
  filePaths?: string[];
  children?: SourcemapNode[];
}

interface SourcemapRoot {
  children?: SourcemapNode[];
}

const colors = {
  reset: "\x1b[0m",
  dim: "\x1b[2m",
  blue: "\x1b[34m",
  yellow: "\x1b[33m",
  red: "\x1b[31m",
};

/** Local wall-clock time as `HH:MM:SS.mmm`. */
function formatTime(date: Date): string {
  const pad = (value: number, length = 2) =>
    String(value).padStart(length, "0");
  return `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}.${pad(date.getMilliseconds(), 3)}`;
}

export class StudioOutputFormatter {
  private sourcemapPath: string;
  private sourcemapModifiedAt = -1;
  private filePathsByInstancePath = new Map<string, string>();

  constructor(sourcemapPath: string) {
    this.sourcemapPath = path.resolve(sourcemapPath);
  }

  /**
   * Format a playtest message like Studio's Output window:
   * `  00:16:28.796  message  -  Server`, with the timestamp and source dimmed.
   */
  public format(output: StudioOutputMessage): string {
    const time = formatTime(new Date(output.timestamp));
    const source = output.source === "server" ? "Server" : "Client";
    const message = this.rewriteSourceLocations(output.message);
    const color = this.getColor(output.messageType);
    const body = color ? `${color}${message}${colors.reset}` : message;
    return `${colors.dim}  ${time}${colors.reset}  ${body}  ${colors.dim}-  ${source}${colors.reset}`;
  }

  private rewriteSourceLocations(message: string): string {
    this.reloadSourcemapIfChanged();

    return message.replace(
      /Script '((?:game\.)?[^']+)', Line (\d+)/g,
      (match, instancePath: string, line: string) => {
        const normalizedInstancePath = instancePath.startsWith("game.")
          ? instancePath
          : `game.${instancePath}`;
        const filePath = this.filePathsByInstancePath.get(
          normalizedInstancePath,
        );
        return filePath ? `Script ${filePath}:${line}` : match;
      },
    );
  }

  private reloadSourcemapIfChanged(): void {
    let modifiedAt: number;
    try {
      modifiedAt = fs.statSync(this.sourcemapPath).mtimeMs;
    } catch {
      return;
    }

    if (modifiedAt === this.sourcemapModifiedAt) {
      return;
    }

    try {
      const sourcemap = JSON.parse(
        fs.readFileSync(this.sourcemapPath, "utf8"),
      ) as SourcemapRoot;
      const filePathsByInstancePath = new Map<string, string>();

      const visit = (node: SourcemapNode, parentPath: string[]): void => {
        const instancePath = [...parentPath, node.name];
        const filePath = node.filePaths?.[0];
        if (filePath) {
          filePathsByInstancePath.set(
            ["game", ...instancePath].join("."),
            filePath.replace(/\\/g, "/"),
          );
        }

        for (const child of node.children ?? []) {
          visit(child, instancePath);
        }
      };

      for (const child of sourcemap.children ?? []) {
        visit(child, []);
      }

      this.filePathsByInstancePath = filePathsByInstancePath;
      this.sourcemapModifiedAt = modifiedAt;
    } catch {
      return;
    }
  }

  private getColor(messageType: string): string | null {
    switch (messageType) {
      case "MessageInfo":
        return colors.blue;
      case "MessageWarning":
        return colors.yellow;
      case "MessageError":
        return colors.red;
      default:
        return null;
    }
  }
}
