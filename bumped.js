const fetch = require('node-fetch');
const Discord = require('discordjs');
const parser = require('rss-parser');
const fs = require('mz/fs');

const getEntry = () => {
    return new Promise((resolve, reject) => {
        parser.parseURL('http://bumped.org/psublog/feed/', (err, res) => {
            if (err) reject(err);
            resolve(res.feed.entries[0]);
        })
    })
}

const buildEmbed = (entry) => {
    let embed = {
        embed: {
            color: 3447003,
            title: entry.title,
            url: entry.link,
            fields: [{
                name: "Summary",
                value: entry.contentSnippet
            }]
        }
    }

    return embed;
}

module.exports = async (client) => {
    const entry = await getEntry();
    const cache = JSON.parse(await fs.readFile('./bumped.json'));

    if (entry.isoDate !== cache.isoDate) {
        await fs.writeFile("bumped.json", `{ "isoDate" : "${entry.isoDate}" }`);
        const guilds = client.guilds.filter(guild => { return client.provider.get(guild, "bumped") });

        for (let guild of guilds) {
            let settings = await client.provider.get(guild[1], "bumped");
            let channel = client.channels.get(settings);

            if (channel.type == "text" && channel.permissionsFor(client.user).has("SEND_MESSAGES") && channel.permissionsFor(client.user).has("READ_MESSAGES") && guild[1].available) {
                channel.send(buildEmbed(entry));
            }
        }
    }
}