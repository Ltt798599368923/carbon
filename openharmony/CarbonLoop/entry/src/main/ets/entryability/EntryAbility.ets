import { UIAbility } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  onWindowStageCreate(windowStage: window.WindowStage): void {
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
