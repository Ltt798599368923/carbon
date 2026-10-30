import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const FACTORS_PATH = fileURLToPath(new URL('../../data/emission-factors.json', import.meta.url));

export async function loadFactors() {
  const source = JSON.parse(await readFile(FACTORS_PATH, 'utf8'));
  return source.factors.map((factor) => ({
    ...factor,
    source: factor.source ?? 'CarbonLoop data/emission-factors.json',
    baseline: factor.baseline ?? '待补充比较基准',
    calculationStatus: factor.calculationStatus ?? 'estimated_demo',
    version: source.version
  }));
}

export async function writeFactors(factors) {
  await writeFile(FACTORS_PATH, JSON.stringify({
    version: new Date().toISOString().slice(0, 10),
    description: 'CarbonLoop managed emission factors',
    factors
  }, null, 2), 'utf8');
}
