import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { ProfileStore } from '../core/ProfileStore';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'V2RayNG', '%{public}s', 'EntryAbility onCreate');
    ProfileStore.init(this.context);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'V2RayNG', 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(0x0000, 'V2RayNG', 'loadContent succeeded');
      // 全面屏适配：状态栏/导航条与页面同色，避免出现白色割裂条
      windowStage.getMainWindow().then((win: window.Window) => {
        let props: window.SystemBarProperties = {
          statusBarColor: '#0B1220',
          statusBarContentColor: '#E5EDFF',
          navigationBarColor: '#0B1220',
          navigationBarContentColor: '#E5EDFF'
        };
        win.setWindowSystemBarProperties(props);
      }).catch((e: Error) => {
        hilog.warn(0x0000, 'V2RayNG', 'set system bar failed: %{public}s', e.message);
      });
    });
  }
}
