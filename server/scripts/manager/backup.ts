/**
 * ARK Server Backup Utility
 * Creates compressed backups of the ARK saved game data
 */

import path from 'path';
import { cpSync, existsSync, mkdirSync, rmSync } from 'fs';
import { spawn } from 'child_process';
import dayjs from 'dayjs';
import { blue, bold, cyan, green, red, yellow } from 'colorette';
import { envVars } from 'root/entrypoint/types.ts';

const { BACKUP_PATH, ARK_DIR, MAX_BACKUPS } = envVars;

/**
 * Creates a formatted timestamp for the backup filename
 */
const getTimestamp = (): string => dayjs().format('YYYY-MM-DD_HH-mm-ss');

/**
 * Creates a backup path if it doesn't exist
 */
const createBackupPathIfNotExists = (): void => {
  if (!existsSync(BACKUP_PATH)) mkdirSync(BACKUP_PATH, { recursive: true });
};

/**
 * Compresses a directory using tar
 */
const compressDirectory = async (sourcePath: string, outputPath: string): Promise<void> =>
  new Promise((resolve, reject) => {
    const tar = spawn('tar', ['-czf', outputPath, '-C', path.dirname(sourcePath), path.basename(sourcePath)]);

    tar.stdout.on('data', (data) => console.log(`tar: ${data}`));
    tar.stderr.on('data', (data) => console.error(red(`tar error: ${data}`)));

    tar.on('close', (code) => {
      if (code === 0) {
        console.log(green('Compression completed successfully'));
        resolve();
      } else {
        reject(new Error(`tar process exited with code ${code}`));
      }
    });
  });

/**
 * Creates a backup of the ARK saved data
 */
const createBackup = async (): Promise<void> => {
  // Create a copy of the save folder to the backup path
  const copyPath = path.join(BACKUP_PATH, 'Saved');

  console.log(blue(`Creating copy of save folder to ${copyPath}...`));
  mkdirSync(copyPath, { recursive: true, mode: 0o755 });
  cpSync(path.join(ARK_DIR, 'ShooterGame/Saved'), copyPath, { recursive: true });

  // Compress the copy
  const archiveName = getTimestamp();
  const archivePath = path.join(BACKUP_PATH, `${archiveName}.tar.gz`);

  console.log(blue(`Compressing ${copyPath} to ${archivePath}...`));
  await compressDirectory(copyPath, archivePath);

  // Remove the copy that isn't compressed
  console.log(blue(`Removing copy of save folder...`));
  rmSync(copyPath, { recursive: true, force: true });

  console.log(green(`Backup created successfully: ${cyan(archivePath)}`));
};

/**
 * Prunes old backups to maintain only the specified number
 */
const pruneOldBackups = (): void => {
  const maxBackupsNum = Number(MAX_BACKUPS);
  if (maxBackupsNum <= 0) return;

  // List all backup files
  const backupFiles = Bun.spawnSync(['ls', '-t', BACKUP_PATH])
    .stdout.toString()
    .trim()
    .split('\n')
    .filter((file) => file.endsWith('.tar.gz'));

  console.log(blue(`Found ${backupFiles.length} backup files`));

  // Delete older backups if exceeding max limit
  if (backupFiles.length > maxBackupsNum) {
    console.log(blue(`Removing ${backupFiles.length - maxBackupsNum} old backups...`));
    const filesToRemove = backupFiles.slice(maxBackupsNum);
    for (const file of filesToRemove) {
      console.log(yellow(`Removing old backup: ${file}`));
      rmSync(path.join(BACKUP_PATH, file), { force: true });
    }
  }

  console.log(green('Backup cleanup completed'));
};

/**
 * Main backup process
 */
const main = async (): Promise<void> => {
  try {
    console.log(bold(cyan('🚀 Starting ARK Server backup process...')));
    createBackupPathIfNotExists();

    // Create and compress backup
    await createBackup();

    // Clean up old backups
    pruneOldBackups();

    // Log success
    console.log(bold(green('✅ Backup completed successfully')));
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    console.error(bold(red(`❌ Backup failed: ${errorMessage}`)));
    process.exit(1);
  }
};

// Execute the backup
main().catch((error) => {
  const errorMessage = error instanceof Error ? error.message : String(error);
  console.error(bold(red(`❌ Unhandled error in backup process: ${errorMessage}`)));
  process.exit(1);
});
