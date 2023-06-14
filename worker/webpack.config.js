const path = require('path');
const NodePolyfillPlugin = require("node-polyfill-webpack-plugin");

module.exports = {
  target: 'webworker',
  entry: path.join(__dirname, './dist/worker.js'),
  output: {
    filename: 'worker.min.js',
    path: path.join(__dirname, 'dist')
  },
  mode: 'production',
  resolve: {
    extensions: ['.js', '.json'],
    plugins: []
  },
  plugins: [
    new NodePolyfillPlugin()
  ]
};