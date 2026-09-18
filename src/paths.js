'use strict';

const path = require('node:path');
const fs = require('node:fs');

const ROOT_DIR = path.join(__dirname, '..');
const DATA_DIR = process.env.COOK_DATA_DIR
  ? path.resolve(process.env.COOK_DATA_DIR)
  : path.join(ROOT_DIR, 'data');

const PATHS = {
  ROOT_DIR,
  DATA_DIR,
  DB_FILE: path.join(DATA_DIR, 'recipes.db'),
  PROFILE_DIR: path.join(DATA_DIR, 'browser-profile'),
  STATE_FILE: path.join(DATA_DIR, 'storage-state.json'),
  COOKIE_FILE: path.join(DATA_DIR, 'cookies.json'),
  DEBUG_DIR: path.join(DATA_DIR, 'debug'),
  IMAGE_DIR: path.join(DATA_DIR, 'images'),
  COVER_DIR: path.join(DATA_DIR, 'images', 'covers'),
  STEP_DIR: path.join(DATA_DIR, 'images', 'steps'),
};

function ensureDirs() {
  for (const dir of [
    PATHS.DATA_DIR,
    PATHS.PROFILE_DIR,
    PATHS.DEBUG_DIR,
    PATHS.IMAGE_DIR,
    PATHS.COVER_DIR,
    PATHS.STEP_DIR,
  ]) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

module.exports = { PATHS, ensureDirs };
