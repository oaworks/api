const path = require('path');

module.exports = {
  target: 'node',
  entry: path.join(__dirname, './dist/server.js'),
  output: {
    filename: 'server.min.js',
    path: path.join(__dirname, 'dist')
  },
  mode: 'production',
  devtool: 'inline-cheap-module-source-map',
  resolve: {
    extensions: ['.js', '.json'],
    plugins: []
  },
  optimization: {
    //minimize: false
  }
};