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

  // Lab 05 task 4: endpoint ใหม่จงใจไม่มี test คลุมเลย เพื่อลด coverage ให้ต่ำกว่า 70%
  // (ทดสอบว่า Quality Gate บล็อก pipeline จริง ไม่ใช่แค่ Unit Test stage เอง)
  app.delete('/tasks/:id', (req, res) => {
    const id = Number(req.params.id);
    const index = tasks.findIndex((t) => t.id === id);
    if (index === -1) {
      return res.status(404).json({ error: 'task not found' });
    }
    tasks.splice(index, 1);
    res.status(204).send();
  });

  app.get('/tasks/stats', (req, res) => {
    const total = tasks.length;
    const done = tasks.filter((t) => t.done).length;
    const pending = total - done;
    let status = 'empty';
    if (total > 0) {
      status = done === total ? 'all-done' : pending === total ? 'none-done' : 'partial';
    }
    res.json({ total, done, pending, status });
  });

  return app;
}

module.exports = { createApp };
