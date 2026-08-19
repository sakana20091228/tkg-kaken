import tkinter as tk
from playsound3 import playsound
import threading

# 警告音を鳴らす関数
def keikoku():
    playsound("アラーム.mp3")

# ボタンを押したら警告音を鳴らす
def keikoku_thread():
    threading.Thread(target=keikoku, daemon=True).start()

# ウィンドウ作成
root = tk.Tk()
root.title("計測アプリ")
root.geometry("600x400")
root.configure(bg="black")

# 「計測中」の文字
label = tk.Label(
    root,
    text="計測中",
    font=("Yu Gothic", 40),
    fg="white",
    bg="black"
)
label.pack(expand=True)

# テスト用ボタン
button = tk.Button(
    root,
    text="警告音を鳴らす",
    font=("Yu Gothic", 16),
    command=keikoku_thread
)
button.pack(pady=20)

root.mainloop()