-- Demo data set for DunstFS (without actual file backings)
-----

-- CREATE TABLE IF NOT EXISTS Files (
--   uuid TEXT PRIMARY KEY NOT NULL, -- a UUIDv4 that is used as a unique identifier
--   user_name TEXT NULL             -- A text that was given by the user as a human-readable name
-- );
-- 
-- CREATE TABLE IF NOT EXISTS DataSets (
--   checksum TEXT PRIMARY KEY NOT NULL,  -- Hash of the file contents (Blake3, 256 bit, no initial key)
--   mime_type TEXT NOT NULL,             -- The mime type
--   creation_date TEXT NOT NULL          -- ISO timestamp of when the data set was created
-- );
-- 
-- CREATE TABLE IF NOT EXISTS Revisions(
--   file TEXT PRIMARY KEY NOT NULL,  -- the file for which this revision was created
--   revision INT NOT NULL,           -- Ever-increasing revision number of the file. The biggest number is the latest revision.
--   dataset TEXT NOT NULL,            -- Key into the dataset table for which file to reference
--   UNIQUE (file, revision),
--   FOREIGN KEY (file) REFERENCES Files (uuid),
--   FOREIGN KEY (dataset) REFERENCES DataSets (checksum) 
-- );
-- 
-- CREATE TABLE IF NOT EXISTS FileTags (
--   file TEXT NOT NULL,  -- The key of the file
--   tag TEXT NOT NULL,   -- The tag name
--   UNIQUE(file,tag),
--   FOREIGN KEY (file) REFERENCES Files(uuid)
-- );
-- 
-- CREATE VIEW IF NOT EXISTS Tags AS SELECT tag, COUNT(file) AS count FROM FileTags GROUP BY tag

INSERT INTO Files (uuid, user_name, last_change) VALUES 
  ('0656707d-bf7a-45ef-ad08-aab956bcbb5e ', NULL, CURRENT_TIMESTAMP),
  ('17f2bde8-9d71-4ceb-93f9-1cb63cc4633e', 'Das kleine Handbuch für angehende Raumfahrer', CURRENT_TIMESTAMP),
  ('f055ec50-5570-4f9b-9b88-671b81cd62cf', 'Donnerwetter', CURRENT_TIMESTAMP);

INSERT INTO DataSets(checksum, mime_type, creation_date) VALUES
  ('59ad4c00ede9148cfe756f2d3595b4e53169f9d8cc609f99b0e5ec117995f024', 'application/octet-stream', '2021-08-28 13:53:59'),
  ('465c05d4e301b9e05bf78b3637bd9515729f5c0fc390ca62c6f4761a7213c946', 'application/pdf', '2021-08-28 13:53:59'),
  ('eea0a4be265a73c8b68ab8ba610265ed7be0d18684d7ff99a2e0db36f278bbb7', 'audio/ogg', '2021-08-28 13:53:59');

INSERT INTO Revisions(file, revision, dataset) VALUES
  ('0656707d-bf7a-45ef-ad08-aab956bcbb5e', 1, '59ad4c00ede9148cfe756f2d3595b4e53169f9d8cc609f99b0e5ec117995f024'),
  ('17f2bde8-9d71-4ceb-93f9-1cb63cc4633e', 1, '465c05d4e301b9e05bf78b3637bd9515729f5c0fc390ca62c6f4761a7213c946'),
  ('f055ec50-5570-4f9b-9b88-671b81cd62cf', 1, 'eea0a4be265a73c8b68ab8ba610265ed7be0d18684d7ff99a2e0db36f278bbb7');

INSERT INTO FileTags (file, tag) VALUES 
  ('0656707d-bf7a-45ef-ad08-aab956bcbb5e', 'keepass'),
  ('0656707d-bf7a-45ef-ad08-aab956bcbb5e', 'passwörter'),
  ('17f2bde8-9d71-4ceb-93f9-1cb63cc4633e', 'Urs Ganse'),
  ('17f2bde8-9d71-4ceb-93f9-1cb63cc4633e', 'raumfahrt'),
  ('17f2bde8-9d71-4ceb-93f9-1cb63cc4633e', 'Bergita Ganse'),
  ('f055ec50-5570-4f9b-9b88-671b81cd62cf', 'unknown artist'),
  ('f055ec50-5570-4f9b-9b88-671b81cd62cf', 'demoscene');