#!/usr/bin/env python3
"""自动登录测试脚本 - 完整 login/logout 循环"""
import sys, json, time
sys.path.insert(0, "E:/workspace/PRJ/P1/scripts")
from mcp_call import mcp_call

def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)

def get_state():
    return mcp_call("editor-application-get-state")

def set_playing(playing: bool):
    return mcp_call("editor-application-set-state", {"isPlaying": playing})

def run_script(code: str, retries=3):
    """执行 C# 脚本，支持重试"""
    for i in range(retries):
        result = mcp_call("script-execute", {
            "className": "Script", "methodName": "Main", "csharpCode": code
        })
        val = result.get("value") or result.get("text", "")
        if val and "null" not in str(val).lower() and "error" not in str(val).lower():
            return val
        log(f"  script-execute 重试 {i+1}/{retries} (got: {result})")
        time.sleep(3)
    return None

# UI 操作脚本
CHECK_UI = 'using UnityEngine; using UnityEngine.UIElements; public class Script { public static object Main() { var docs = Object.FindObjectsOfType<UIDocument>(); string r = ""; foreach (var doc in docs) { if (doc.rootVisualElement == null) continue; if (doc.rootVisualElement.Q("SplashAnnouncement") != null) r += "ANN,"; if (doc.rootVisualElement.Q<Button>("btn-login") != null) r += "LOGIN,"; if (doc.rootVisualElement.Q<Button>("btn-continue") != null) r += "CONT,"; } var pm = GameObject.Find("[PlayerManager]"); if (pm != null && pm.transform.childCount > 0) r += "INGAME,"; return r; } }'

CLOSE_ANN = 'using UnityEngine; using UnityEngine.UIElements; public class Script { public static object Main() { var docs = Object.FindObjectsOfType<UIDocument>(); foreach (var doc in docs) { if (doc.rootVisualElement == null) continue; var a = doc.rootVisualElement.Q("SplashAnnouncement"); if (a == null) continue; var b = a.Q<Button>("btn-close"); if (b == null) return "no-btn"; using (var e = ClickEvent.GetPooled()) { e.target = b; b.SendEvent(e); } return "OK"; } return "no-ann"; } }'

CLICK_LOGIN = 'using UnityEngine; using UnityEngine.UIElements; public class Script { public static object Main() { var docs = Object.FindObjectsOfType<UIDocument>(); foreach (var doc in docs) { if (doc.rootVisualElement == null) continue; var b = doc.rootVisualElement.Q<Button>("btn-login"); if (b == null) continue; using (var e = ClickEvent.GetPooled()) { e.target = b; b.SendEvent(e); } return "OK"; } return "no-btn"; } }'

CLICK_CONTINUE = 'using UnityEngine; using UnityEngine.UIElements; public class Script { public static object Main() { var docs = Object.FindObjectsOfType<UIDocument>(); foreach (var doc in docs) { if (doc.rootVisualElement == null) continue; var b = doc.rootVisualElement.Q<Button>("btn-continue"); if (b == null) continue; using (var e = ClickEvent.GetPooled()) { e.target = b; b.SendEvent(e); } return "OK"; } return "no-btn"; } }'

def do_login():
    """执行登录流程，返回 True/False"""
    # 进入 Play 模式
    state = get_state()
    if not state.get("IsPlaying"):
        log("进入 Play 模式...")
        set_playing(True)
        # 等待 Play 模式生效
        for i in range(20):
            time.sleep(2)
            s = get_state()
            if s.get("IsPlaying"):
                log("Play 模式已激活")
                break
        else:
            log("ERROR: 无法进入 Play 模式")
            return False
        time.sleep(5)  # 额外等待初始化

    # 检测 UI 状态
    log("检测 UI 状态...")
    ui = run_script(CHECK_UI)
    if ui is None:
        log("ERROR: 无法检测 UI")
        return False
    log(f"  UI 状态: {ui}")

    if "INGAME" in ui:
        log("已在游戏中，跳过登录")
        return True

    # 关闭公告
    if "ANN" in ui:
        log("关闭公告...")
        run_script(CLOSE_ANN)
        time.sleep(3)

    # 点击登录
    if "LOGIN" in ui:
        log("点击登录...")
        run_script(CLICK_LOGIN)
        time.sleep(10)

    # 检查是否需要点继续
    ui2 = run_script(CHECK_UI)
    log(f"  登录后 UI: {ui2}")
    if ui2 and "CONT" in ui2 and "INGAME" not in ui2:
        log("点击继续...")
        run_script(CLICK_CONTINUE)
        time.sleep(15)

    # 验证
    ui3 = run_script(CHECK_UI)
    log(f"  最终 UI: {ui3}")
    return ui3 is not None and "INGAME" in ui3

def do_logout():
    """退出登录"""
    log("退出 Play 模式...")
    set_playing(False)
    for i in range(15):
        time.sleep(2)
        s = get_state()
        if not s.get("IsPlaying"):
            log("已退出 Play 模式")
            return True
    log("ERROR: 退出超时")
    return False

def main():
    rounds = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    results = []

    for i in range(1, rounds + 1):
        log(f"===== 第 {i} 轮 =====")

        login_ok = do_login()
        log(f"  登录: {'OK' if login_ok else 'FAIL'}")

        logout_ok = do_logout()
        log(f"  退出: {'OK' if logout_ok else 'FAIL'}")

        results.append((login_ok, logout_ok))
        log(f"  第 {i} 轮结果: login={'OK' if login_ok else 'FAIL'} logout={'OK' if logout_ok else 'FAIL'}")
        time.sleep(3)  # 冷却

    log("===== 总结 =====")
    for i, (l, o) in enumerate(results, 1):
        log(f"  第 {i} 轮: login={'OK' if l else 'FAIL'} logout={'OK' if o else 'FAIL'}")

    total = len(results)
    login_ok = sum(1 for l, _ in results if l)
    logout_ok = sum(1 for _, o in results if o)
    log(f"  成功率: login={login_ok}/{total} logout={logout_ok}/{total}")

if __name__ == "__main__":
    main()
