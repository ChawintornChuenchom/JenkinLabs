const request = require('supertest');
const { createApp } = require('../src/app');

describe('taskflow-lab API', () => {
  let app;

  beforeEach(() => {
    app = createApp();
  });

  test('GET /tasks returns an empty list initially', async () => {
    const res = await request(app).get('/tasks');
    expect(res.status).toBe(200);
    expect(res.body).toEqual([]);
  });

  test('POST /tasks creates a task', async () => {
    const res = await request(app).post('/tasks').send({ title: 'write report' });
    expect(res.status).toBe(201);
    expect(res.body.title).toBe('write report');
    expect(res.body.done).toBe(false);
  });

  test('POST /tasks without title returns 400', async () => {
    const res = await request(app).post('/tasks').send({});
    expect(res.status).toBe(400);
  });

  test('PATCH /tasks/:id/done marks a task done', async () => {
    const created = await request(app).post('/tasks').send({ title: 'ship it' });
    const res = await request(app).patch(`/tasks/${created.body.id}/done`);
    expect(res.status).toBe(200);
    expect(res.body.done).toBe(true);
  });

  test('PATCH on missing task returns 404', async () => {
    const res = await request(app).patch('/tasks/999/done');
    expect(res.status).toBe(404);
  });

  test('GET /health reports ok', async () => {
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
  });
});
