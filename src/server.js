const { createApp } = require('./app');

const PORT = process.env.PORT || 8080;
createApp().listen(PORT, () => {
  console.log(`taskflow-lab API listening on port ${PORT}`);
});
