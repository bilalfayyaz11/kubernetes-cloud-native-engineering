const fs = require('fs');
const path = require('path');
const UglifyJS = require('uglify-js');

const sourcePath = path.join('public', 'app.js');
const distPath = 'dist';

fs.mkdirSync(distPath, { recursive: true });

const sourceCode = fs.readFileSync(sourcePath, 'utf8');

const minified = UglifyJS.minify(sourceCode);

if (minified.error) {
    console.error('JavaScript minification failed:', minified.error);
    process.exit(1);
}

fs.writeFileSync(
    path.join(distPath, 'app.min.js'),
    minified.code
);

let html = fs.readFileSync(
    path.join('public', 'index.html'),
    'utf8'
);

html = html.replace('app.js', 'app.min.js');
html = html.replace(/\s+/g, ' ').trim();

fs.writeFileSync(
    path.join(distPath, 'index.html'),
    html
);

console.log('Build completed successfully.');
