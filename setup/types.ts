export interface ConfigDifference {
  path: string;
  expectedValue: any;
  expectedType: string;
  actualValue?: any;
  actualType?: string;
  isMissing: boolean;
}

export interface DownloadTarget {
  url: string;
  path: string;
}

export interface CompilationOptions {
  envVars: Record<string, string>;
  templatePath: string;
  outputPath: string;
}

export interface ComparisonOptions {
  compiledConfigPath: string;
  customConfigPath: string;
  updateConfig: boolean;
}
