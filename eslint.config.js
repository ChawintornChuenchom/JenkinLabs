const security = require('eslint-plugin-security');

module.exports = [
  {
    files: ['src/**/*.js'],
    plugins: { security },
    rules: {
      ...security.configs.recommended.rules,
    },
    languageOptions: {
      ecmaVersion: 2021,
      sourceType: 'commonjs',
    },
  },
];
