import { common, UIAbility } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';
import { window } from '@kit.ArkUI';

export let carbonPreferences: preferences.Preferences | null = null;
export let carbonContext: common.UIAbilityContext | null = null;

export default class EntryAbility extends UIAbility {
  onWindowStageCreate(windowStage: window.WindowStage): void {
    carbonContext = this.context;
    carbonPreferences = preferences.getPreferencesSync(this.context, { name: 'carbonloop_data' });
    windowStage.loadContent('pages/Index', (error: BusinessError) => {
      if (error.code) {
        console.error(`CarbonLoop load page failed: ${error.code}, ${error.message}`);
      }
    });
  }

  onWindowStageDestroy(): void {
    // Release page-level resources here when the product adds distributed sync.
  }

  onForeground(): void {}
  onBackground(): void {}
}
