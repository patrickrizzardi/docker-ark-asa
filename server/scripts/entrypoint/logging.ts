import { execSync, spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { envVars } from 'root/entrypoint/types.ts';

const { LOG_FILE, GAME_LOG_FILE, API_LOG_FILE, WINE_LOG_FILE } = envVars;

/**
 * Function to tail multiple log files
 */
export const tailLogs = (): void => {
  const tails: Array<string> = [];

  setInterval(() => {
    // Check if main log file exists and start tailing
    if (existsSync(LOG_FILE) && !tails.includes(LOG_FILE)) {
      startTailingLog(LOG_FILE, tails);
    }

    // Check other log patterns
    for (const logPattern of [GAME_LOG_FILE, API_LOG_FILE, WINE_LOG_FILE]) {
      tailLatestLogFile(logPattern, tails);
    }
  }, 5000);
};

/**
 * Start tailing a specific log file
 */
export const startTailingLog = (logFile: string, tailsList: Array<string>): void => {
  const tailProcess = spawn('tail', ['-F', logFile]);

  // Using direct process.stdout pipe is more efficient for streaming data than console.log
  // as it avoids formatting overhead and maintains real-time streaming behavior
  // @ts-expect-error - Ignoring type error for stream compatibility
  tailProcess.stdout.pipe(process.stdout);
  // @ts-expect-error - Ignoring type error for stream compatibility
  tailProcess.stderr.pipe(process.stderr);
  tailsList.push(logFile);
};

/**
 * Find and tail the latest log file matching a pattern
 */
export const tailLatestLogFile = (logPattern: string, tailsList: Array<string>): void => {
  try {
    // Use ls to find latest log for pattern
    const latestLog = execSync(`ls -t ${logPattern} 2>/dev/null | head -n 1`, { encoding: 'utf8' }).trim();

    if (latestLog && !tailsList.includes(latestLog)) {
      startTailingLog(latestLog, tailsList);
    }
  } catch (_error) {
    // Ignore errors from ls command
  }
};
