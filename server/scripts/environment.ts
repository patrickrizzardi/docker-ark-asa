/* eslint-disable @typescript-eslint/naming-convention */
declare module 'bun' {
  export interface Env {
    ARK_DIR: string;
    STEAM_DIR: string;
    ASA_APPID: string;
    LOG_FILE: string;
    GAME_LOG_FILE: string;
    API_LOG_FILE: string;
    WINE_LOG_FILE: string;
    BACKUP_PATH: string;
    MAX_BACKUPS: number;
  }
}
