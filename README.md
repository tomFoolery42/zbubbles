Just a simplish version of bluebubbles client for linux
For now you need 2 json files. One to point to where the bluebubbles server is
another to list out the contacts

config.json
{
        "host":           "http://<HOST_NAME>:<PORT>/api/v1",
        "contacts_file":  "contacts.json",
        "password":       "<BLUEBUBBLES_PASSWORD"
}

contacts.json
[
    {
        "display_name": "john",
        "number": "+15555555555",
    },
...
]

This was more of a way for me to learn zig. Some things might seem kinda weird.
Its because I wanted to see how different things worked in zig.

Uses zig 0.14!
Uses Vaxis for TUI

Current Features:
    text messages
    web sockets (for notifications)
    lists that an image was sent
    typing indication
    initial sync (no offline data)
    mark as read
    terminal title (chat name)

Future Features:
    image support
    create new chats
    reactions support
    pull contacts (from mac, maybe)
    schema message pools
    system notifications when not on chat with new message
