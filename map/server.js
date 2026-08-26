const express = require("express");
const fs = require("fs");
const path = require("path");

const app = express();

const port = 3002;

app.use(express.json());

app.get("/points/:file", (req, res) => {
  const { file } = req.params;
  const data = fs.readFileSync(`../data/calculated/${file}.json`, "utf-8");
  const results = JSON.parse(data);
  res.send(results);
});

app.get("/grid-points", (req, res) => {
  const { file } = req.params;
  const data = fs.readFileSync(`../data/grid/names.json`, "utf-8");
  const results = JSON.parse(data);
  res.send(results);
});

app.get("/grid-points2", (req, res) => {
  const { file } = req.params;
  const data = fs.readFileSync(`../data/grid/belgium.json`, "utf-8");
  const results = JSON.parse(data);
  res.send(results);
});

app.get("/grid", (req, res) => {
  res.sendFile(path.join(__dirname, "public", "grid.html"));
});

app.get("/heat", (req, res) => {
  res.sendFile(path.join(__dirname, "public", "heatmap.html"));
});

app.get("/analyze", (req, res) => {
  res.sendFile(path.join(__dirname, "public", "analyze.html"));
});

app.get("/map", (req, res) => {
  res.sendFile(path.join(__dirname, "public", "map.html"));
});

app.get("/data", async (req, res) => {
  const response = await fetch("http://localhost:8000/data");
  const json = await response.json();
  res.send(json);
});

app.get("/website", (req, res) => {
  res.sendFile(path.join(__dirname, "public", "index.html"));
});

app.get("/raw", (req, res) => {
  res.sendFile(path.join(__dirname, "public", "raw.html"));
});

app.listen(port, () => {
  console.log(`Server running at http://localhost:${port}`);
});
