const express = require('express');

const app = express();
const port = process.env.PORT || 3000;

app.get('/', (req, res) => {
  res.json({
    message: 'Kubernetes CI/CD application',
    version: process.env.APP_VERSION || 'development',
    timestamp: new Date().toISOString()
  });
});

app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy'
  });
});

app.listen(port, '0.0.0.0', () => {
  console.log(`Application listening on port ${port}`);
});
