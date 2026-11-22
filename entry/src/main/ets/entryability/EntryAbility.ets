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
      windowStage.getMainWindow().then((win: window.Window) => {
        // 全面屏沉浸：内容延伸到状态栏/导航条之下，消除顶部/底部割裂白条
        win.setWindowLayoutFullScreen(true);
        let props: window.SystemBarProperties = {
          statusBarContentColor: '#E5EDFF',
          navigationBarContentColor: '#E5EDFF'
        };
        win.setWindowSystemBarProperties(props);
        // 记录安全区高度（px），页面用 px2vp 换算后做内容避让
        let sys = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        let nav = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        AppStorage.setOrCreate('sysBarHeightPx', sys.topRect.height);
        AppStorage.setOrCreate('navBarHeightPx', nav.bottomRect.height);
        hilog.info(0x0000, 'V2RayNG', 'immersive ok, sys=%{public}d nav=%{public}d',
          sys.topRect.height, nav.bottomRect.height);
      }).catch((e: Error) => {
        hilog.warn(0x0000, 'V2RayNG', 'immersive setup failed: %{public}s', e.message);
      });
    });
  }
}
