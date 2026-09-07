"""Broker MQTT thật, chỉ bind loopback, dùng riêng cho bài mô phỏng."""
import asyncio
import logging
import os
from pathlib import Path
from amqtt.broker import Broker


async def run():
    logging.basicConfig(level=logging.ERROR)
    broker = Broker({
        "listeners": {"default": {"type": "tcp", "bind": f"127.0.0.1:{int(os.environ['PERF_MQTT_PORT'])}"}},
        "plugins": {"amqtt.plugins.authentication.AnonymousAuthPlugin": {"allow_anonymous": True}},
    })
    await broker.start()
    print("LOCAL_BROKER_READY", flush=True)
    try:
        while not Path(os.environ["PERF_RUN_DIR"], "stop-broker").exists():
            await asyncio.sleep(0.2)
    finally:
        await broker.shutdown()


if __name__ == "__main__":
    asyncio.run(run())
