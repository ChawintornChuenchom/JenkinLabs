const express = require('express');

function createApp() {
  const app = express();
  app.use(express.json());

  let tasks = [];
  let nextId = 1;

  app.get('/health', (req, res) => {
    res.json({ status: 'ok' });
  });

  app.get('/tasks', (req, res) => {
    res.json(tasks);
  });

  app.post('/tasks', (req, res) => {
    const { title } = req.body;
    if (!title) {
      return res.status(400).json({ error: 'title is required' });
    }
    const task = { id: nextId++, title, done: false };
    tasks.push(task);
    res.status(201).json(task);
  });

  app.patch('/tasks/:id/done', (req, res) => {
    const id = Number(req.params.id);
    const task = tasks.find((t) => t.id === id);
    if (!task) {
      return res.status(404).json({ error: 'task not found' });
    }
    task.done = true;
    res.json(task);
  });

  return app;
}

module.exports = { createApp };
