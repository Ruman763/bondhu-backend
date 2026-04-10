-- Fixed UUID so the Node socket layer can persist global chat messages.
INSERT INTO chats (id, type, name)
VALUES ('00000000-0000-0000-0000-000000000001'::uuid, 'global', 'Global Chat')
ON CONFLICT (id) DO NOTHING;
