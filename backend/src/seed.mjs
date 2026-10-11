import { writeFile } from 'node:fs/promises';
import { storePath } from './store.mjs';
console.log(`Store is initialized at ${storePath()}`);
