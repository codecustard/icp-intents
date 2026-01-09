// Simple structured logger with colored console output

export enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3,
}

// ANSI color codes
const colors = {
  reset: '\x1b[0m',
  bright: '\x1b[1m',
  dim: '\x1b[2m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  magenta: '\x1b[35m',
  cyan: '\x1b[36m',
  gray: '\x1b[90m',
};

class Logger {
  private minLevel: LogLevel = LogLevel.INFO;

  setLevel(level: LogLevel) {
    this.minLevel = level;
  }

  private shouldLog(level: LogLevel): boolean {
    return level >= this.minLevel;
  }

  private formatTimestamp(): string {
    const now = new Date();
    return now.toISOString();
  }

  private formatMessage(level: string, message: string, context?: Record<string, any>): string {
    const timestamp = this.formatTimestamp();
    const contextStr = context ? ` ${JSON.stringify(context)}` : '';
    return `[${timestamp}] ${level} ${message}${contextStr}`;
  }

  debug(message: string, context?: Record<string, any>) {
    if (!this.shouldLog(LogLevel.DEBUG)) return;
    const formatted = this.formatMessage('DEBUG', message, context);
    console.log(`${colors.gray}${formatted}${colors.reset}`);
  }

  info(message: string, context?: Record<string, any>) {
    if (!this.shouldLog(LogLevel.INFO)) return;
    const formatted = this.formatMessage('INFO', message, context);
    console.log(`${colors.blue}${formatted}${colors.reset}`);
  }

  warn(message: string, context?: Record<string, any>) {
    if (!this.shouldLog(LogLevel.WARN)) return;
    const formatted = this.formatMessage('WARN', message, context);
    console.log(`${colors.yellow}${formatted}${colors.reset}`);
  }

  error(message: string, context?: Record<string, any>) {
    if (!this.shouldLog(LogLevel.ERROR)) return;
    const formatted = this.formatMessage('ERROR', message, context);
    console.error(`${colors.red}${formatted}${colors.reset}`);
  }

  success(message: string, context?: Record<string, any>) {
    if (!this.shouldLog(LogLevel.INFO)) return;
    const formatted = this.formatMessage('SUCCESS', message, context);
    console.log(`${colors.green}${formatted}${colors.reset}`);
  }
}

// Export singleton instance
export const logger = new Logger();
