import { copyFileSync, renameSync, unlinkSync } from 'node:fs';

// Function to safely move files across filesystems
export function safeMove(src: string, dest: string): void {
  try {
    // First try with rename (faster if on same filesystem)
    renameSync(src, dest);
  } catch (error) {
    if (error instanceof Error && error.message.includes('cross-device link')) {
      // Fall back to copy + delete if across filesystems
      console.log(`Cross-device move detected, copying instead: ${src} -> ${dest}`);
      copyFileSync(src, dest);
      unlinkSync(src);
    } else {
      // If it's some other error, re-throw it
      throw error;
    }
  }
}
