import { chromium } from '@playwright/test';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const SCREENSHOT_DIR = path.resolve('screenshots');
const TARGET_ORG = 'vf-scratch';

function runSf(command) {
    return execSync(`sf ${command} --target-org ${TARGET_ORG}`, {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'pipe']
    });
}

function getOrgDetails() {
    const orgJson = runSf('org display --json');
    return JSON.parse(orgJson).result;
}

function getFrontdoorUrl() {
    const openJson = runSf('org open --url-only --json');
    return JSON.parse(openJson).result.url;
}

function getLexBase(instanceUrl) {
    return instanceUrl.replace('.my.salesforce.com', '.lightning.force.com');
}

async function screenshot(page, stepName) {
    if (!fs.existsSync(SCREENSHOT_DIR)) {
        fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });
    }
    const safeName = stepName.toLowerCase().replace(/[^a-z0-9]+/g, '-');
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, `${safeName}.png`), fullPage: true });
}

async function runStep(stepName, checkDescription, action) {
    console.log(`STEP: ${stepName} — ${checkDescription}`);
    await action();
}

async function main() {
    const steps = [];
    const org = getOrgDetails();
    const lexBase = getLexBase(org.instanceUrl);
    const frontdoorUrl = getFrontdoorUrl();
    const dashboardUrl = `${lexBase}/lightning/n/Data_Hygiene_Dashboard`;

    const browser = await chromium.launch({ headless: false, slowMo: 300 });
    const context = await browser.newContext();
    const page = await context.newPage();

    let dirtyCountBefore = 0;

    try {
        await runStep(
            'Login',
            'Authenticate into scratch org via frontdoor URL',
            async () => {
                await page.goto(frontdoorUrl);
                await page.waitForLoadState('domcontentloaded');
                await page.waitForTimeout(3000);
                await screenshot(page, '01-login');
            }
        );
        steps.push({ name: 'Login', passed: true });

        await runStep(
            'Open Dashboard',
            'Navigate directly to Data Hygiene Dashboard tab',
            async () => {
                await page.goto(dashboardUrl);
                await page.waitForLoadState('domcontentloaded');
                await page.waitForTimeout(3000);
                await screenshot(page, '02-open-dashboard');
            }
        );

        const titleVisible = await page.getByText('Data Hygiene Dashboard').first().isVisible();
        if (!titleVisible) {
            throw new Error('Dashboard title was not visible.');
        }
        steps.push({ name: 'Open Dashboard', passed: true });

        await runStep(
            'Verify Stats',
            'Confirm three stat cards render',
            async () => {
                await page.getByText('Records Scanned').waitFor({ state: 'visible' });
                await page.getByText('Dirty Records').waitFor({ state: 'visible' });
                await page.getByText('Cleaned Today').waitFor({ state: 'visible' });
                await screenshot(page, '03-stats-cards');
            }
        );
        steps.push({ name: 'Verify Stats', passed: true });

        await runStep(
            'Verify Dirty List',
            'Confirm at least one dirty Lead appears in the list',
            async () => {
                const dirtyQuery = runSf(
                    "data query --json --query \"SELECT COUNT() FROM Lead WHERE Hygiene_Status__c = 'Dirty' OR Hygiene_Status__c = NULL\""
                );
                dirtyCountBefore = JSON.parse(dirtyQuery).result.totalSize;
                if (dirtyCountBefore < 1) {
                    throw new Error('Expected at least one dirty Lead from seed data.');
                }
                await page.locator('.record-card').first().waitFor({ state: 'visible', timeout: 15000 });
                await screenshot(page, '04-dirty-list');
            }
        );
        steps.push({ name: 'Verify Dirty List', passed: true });

        await runStep(
            'Select Lead',
            'Click the first dirty Lead and verify detail panel',
            async () => {
                await page.locator('.record-card').first().click();
                await page.getByRole('button', { name: 'Clean Selected Record' }).waitFor({ state: 'visible' });
                await screenshot(page, '05-selected-lead');
            }
        );
        steps.push({ name: 'Select Lead', passed: true });

        await runStep(
            'Clean Selected',
            'Run one-click cleanup and wait for success feedback',
            async () => {
                await page.getByRole('button', { name: 'Clean Selected Record' }).click();
                await page.waitForTimeout(4000);
                const toastOrResult =
                    (await page.locator('.slds-notify__content').count()) > 0 ||
                    (await page.locator('.result-panel').count()) > 0;
                if (!toastOrResult) {
                    throw new Error('Expected a success toast or result panel after cleanup.');
                }
                await screenshot(page, '06-after-clean');
            }
        );
        steps.push({ name: 'Clean Selected', passed: true });

        await runStep(
            'Verify Improvement',
            'Confirm dirty count decreased via SOQL after cleanup',
            async () => {
                const dirtyQueryAfter = runSf(
                    "data query --json --query \"SELECT COUNT() FROM Lead WHERE Hygiene_Status__c = 'Dirty' OR Hygiene_Status__c = NULL\""
                );
                const dirtyCountAfter = JSON.parse(dirtyQueryAfter).result.totalSize;
                if (dirtyCountAfter >= dirtyCountBefore) {
                    throw new Error(
                        `Dirty count did not decrease (${dirtyCountBefore} -> ${dirtyCountAfter}).`
                    );
                }
                await screenshot(page, '07-verified-improvement');
            }
        );
        steps.push({ name: 'Verify Improvement', passed: true });

        console.log('\nPlaywright validation complete.');
        steps.forEach((step) => console.log(`${step.name}: ✅`));
        process.exit(0);
    } catch (error) {
        console.error(`\nFAILED: ${error.message}`);
        steps.forEach((step) => console.log(`${step.name}: ${step.passed ? '✅' : '❌'}`));
        await screenshot(page, 'failure');
        process.exit(1);
    } finally {
        await browser.close();
    }
}

main();
