const path = require('path');

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
  }
};