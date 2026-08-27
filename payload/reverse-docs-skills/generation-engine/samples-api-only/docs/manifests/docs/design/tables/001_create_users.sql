CREATE TABLE users (
  id BIGINT PRIMARY KEY,
  email VARCHAR(255) NOT NULL,
  organization_id BIGINT,
  created_at TIMESTAMP NOT NULL,
  FOREIGN KEY (organization_id) REFERENCES organizations(id)
);
