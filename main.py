import tkinter as tk
from playsound3 import playsound
import threading


# =========================
# 警告音を鳴らす
# =========================
def keikoku_onsei():
    playsound("アラーム.mp3")


# =========================
# 警告画面を赤⇄黄色に点滅
# =========================
def keikoku_hyouji():
    if not warning:
        return

    if root.cget("bg") == "red":
        root.configure(bg="yellow")
        label.configure(
            bg="yellow",
            fg="black"
        )
    else:
        root.configure(bg="red")
        label.configure(
            bg="red",
            fg="white"
        )

    # 0.5秒後にもう一度点滅
    root.after(500, keikoku_hyouji)


# =========================
# 警告を開始
# =========================
def keikoku_start():
    global warning

    # すでに警告中なら何もしない
    if warning:
        return

    warning = True

    # -------------------------
    # 警告画面を表示
    # -------------------------
    label.configure(
        text="警告！",
        font=("Yu Gothic", 50)
    )

    # 最初は赤
    root.configure(bg="red")
    label.configure(
        bg="red",
        fg="white"
    )

    # -------------------------
    # 警告音を鳴らす
    # -------------------------
    threading.Thread(
        target=keikoku_onsei,
        daemon=True
    ).start()

    # -------------------------
    # 画面の点滅を開始
    # -------------------------
    root.after(500, keikoku_hyouji)


# =========================
# 警告を解除
# =========================
def keikoku_stop():
    global warning

    warning = False

    # 黒画面に戻す
    root.configure(bg="black")

    label.configure(
        text="計測中",
        font=("Yu Gothic", 40),
        fg="white",
        bg="black"
    )


# =========================
# テストボタン
# =========================
def test():
    if warning:
        keikoku_stop()
    else:
        keikoku_start()


# =========================
# 初期設定
# =========================
warning = False

root = tk.Tk()

root.title("計測アプリ")
root.geometry("600x400")
root.configure(bg="black")


# =========================
# 「計測中」の表示
# =========================
label = tk.Label(
    root,
    text="計測中",
    font=("Yu Gothic", 40),
    fg="white",
    bg="black"
)

label.pack(expand=True)


# =========================
# テストボタン
# =========================
button = tk.Button(
    root,
    text="警告テスト",
    font=("Yu Gothic", 16),
    command=test
)

button.pack(pady=20)


# =========================
# アプリ開始
# =========================
root.mainloop()