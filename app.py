from flask import Flask, send_file

app = Flask(__name__)

@app.route("/")
def home():
    return send_file("index.html")

app.run(host="0.0.0.0", port=80)
