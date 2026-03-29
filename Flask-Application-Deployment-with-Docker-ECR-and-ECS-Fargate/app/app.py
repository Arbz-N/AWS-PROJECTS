from flask import Flask, render_template

app = Flask(__name__)


@app.route('/')
def index():
    return render_template('index.html')
    # renders templates/index.html


if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0')
    # host='0.0.0.0' listens on all interfaces so the browser can reach it
    # host='127.0.0.1' would restrict access to localhost only