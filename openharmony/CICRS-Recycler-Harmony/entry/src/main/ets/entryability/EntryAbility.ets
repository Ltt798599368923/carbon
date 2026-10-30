import { UIAbility } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';
import { window } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { CicrsFactorCatalog } from '../model/CicrsModel';
import { cicrsRepository } from '../service/CicrsRepository';

export let cicrsPreferences: preferences.Preferences | null = null;
export let cicrsFactorCatalog: CicrsFactorCatalog | null = null;

export default class EntryAbility extends UIAbility {
  onWindowStageCreate(windowStage: window.WindowStage): void {
    cicrsPreferences = preferences.getPreferencesSync(this.context, { name: 'cicrs_data' });
    try {
      const factorBytes: Uint8Array = this.context.resourceManager.getRawFileContentSync('cicrs-factors.json');
      const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
      const factorText: string = decoder.decode(factorBytes);
      cicrsFactorCatalog = JSON.parse(factorText) as CicrsFactorCatalog;
      cicrsRepository.initialize(cicrsPreferences, cicrsFactorCatalog);
    } catch (error) {
      console.error(`CICRS failed to load local carbon factor configuration: ${error}`);
    }
    windowStage.loadContent('pages/Index', (error: BusinessError) => {
      if (error.code) {
        console.error(`CICRS load page failed: ${error.code}, ${error.message}`);
      }
    });
  }

  onWindowStageDestroy(): void {
    // Release page-level resources here when the product adds distributed sync.
  }

  onForeground(): void {}
  onBackground(): void {}
}
