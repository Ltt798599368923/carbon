import { UIAbility, Want, window } from '@kit.AbilityKit';

export default class EntryAbility extends UIAbility {
  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (error) => {
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
